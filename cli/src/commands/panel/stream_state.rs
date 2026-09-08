// Coalesces producer observations and tracks acknowledged task state.
// Exports stream state and batching internals to the parent transport.
// Dependencies: parent snapshot, JSON merge helpers, and std time.
use super::*;

pub(super) struct Batcher {
    pub(super) pending: bool,
    pub(super) deadline: Option<Instant>,
    pub(super) window: Duration,
}
impl Batcher {
    pub(super) fn new(window: Duration) -> Self { Self { pending: false, deadline: None, window } }
    pub(super) fn push(&mut self, now: Instant) { self.pending = true; self.deadline.get_or_insert(now + self.window); }
    pub(super) fn due(&self, now: Instant) -> bool { self.pending && self.deadline.is_some_and(|deadline| now >= deadline) }
    pub(super) fn force(&mut self) { self.pending = true; self.deadline = Some(Instant::now()); }
    pub(super) fn clear(&mut self) { self.pending = false; self.deadline = None; }
}

pub(super) struct StreamState {
    pub(super) acknowledged: Value,
    pub(super) desired: Value,
    pub(super) sequence: u64,
    pub(super) in_flight: Option<Value>,
    pub(super) ambiguous: bool,
    pub(super) batch: Batcher,
}
impl StreamState {
    pub(super) fn from_snapshot(snapshot: Snapshot) -> Result<Self, Box<dyn Error>> {
        if !snapshot.task.is_object() { return Err("panel snapshot task must be an object".into()); }
        Ok(Self { acknowledged: snapshot.task.clone(), desired: snapshot.task, sequence: snapshot.sequence, in_flight: None, ambiguous: false, batch: Batcher::new(BATCH_WINDOW) })
    }

    pub(super) fn add_partial(&mut self, partial: Value) -> Result<(), Box<dyn Error>> {
        let partial = partial.as_object().ok_or("each stream line must be a JSON object")?;
        merge_object(self.desired.as_object_mut().ok_or("panel task must be an object")?, partial);
        self.batch.push(Instant::now());
        Ok(())
    }

    pub(super) fn ready(&self, now: Instant) -> bool { self.in_flight.is_none() && self.batch.due(now) }

    pub(super) fn acknowledge(&mut self, sequence: u64) -> bool {
        let Some(target) = self.in_flight.take() else { return false; };
        self.acknowledged = target;
        self.sequence = sequence;
        true
    }

    pub(super) fn resync(&mut self, snapshot: Snapshot) -> Result<(), Box<dyn Error>> {
        if !snapshot.task.is_object() { return Err("panel resync task must be an object".into()); }
        self.acknowledged = snapshot.task;
        self.sequence = snapshot.sequence;
        self.in_flight = None;
        if !same_value(&self.desired, &self.acknowledged) { self.batch.force(); }
        Ok(())
    }

    pub(super) fn reconnect(&mut self, snapshot: Snapshot) -> Result<(), Box<dyn Error>> {
        self.ambiguous = self.in_flight.as_ref().is_some_and(|task| !same_value(task, &snapshot.task));
        self.resync(snapshot)
    }

    pub(super) fn finished(&self) -> bool { self.in_flight.is_none() && !self.batch.pending && !self.ambiguous }
}

