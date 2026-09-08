// Stream state machine regression tests.
// Dependencies: parent stream implementation and serde_json.
use super::*;

    #[test]
    fn batching_waits_for_window_and_coalesces() {
        let start = Instant::now();
        let mut batch = Batcher::new(Duration::from_millis(20));
        batch.push(start);
        assert!(!batch.due(start + Duration::from_millis(19)));
        assert!(batch.due(start + Duration::from_millis(20)));
        batch.push(start + Duration::from_millis(1));
        assert_eq!(batch.deadline, Some(start + Duration::from_millis(20)));
        let mut state = StreamState::from_snapshot(Snapshot { sequence: 0, task: json!({}) }).expect("snapshot");
        state.add_partial(json!({"metrics":{"a":1}})).expect("partial");
        state.add_partial(json!({"metrics":{"b":2}})).expect("partial");
        assert_eq!(state.desired, json!({"metrics":{"a":1,"b":2}}));
    }

    #[test]
    fn resync_rebases_to_snapshot_without_losing_desired_state() {
        let mut state = StreamState::from_snapshot(Snapshot { sequence: 4, task: json!({"done": 1}) }).expect("snapshot");
        state.add_partial(json!({"done": 2})).expect("partial");
        state.batch.force();
        state.in_flight = Some(state.desired.clone());
        state.batch.clear();
        state.resync(Snapshot { sequence: 7, task: json!({"done": 1, "note":"server"}) }).expect("resync");
        assert_eq!(state.sequence, 7);
        assert!(state.in_flight.is_none());
        assert_eq!(diff_values(&state.acknowledged, &state.desired, "/task").len(), 1);
    }

    #[test]
    fn fenced_epoch_stops_the_producer_rather_than_retrying() {
        // The earlier test asserted only how relay_error formats a string, so deleting the
        // stop entirely left all 179 tests green.
        for code in ["lease_conflict", "fenced_epoch"] {
            let frame = RelayFrame { kind: "error".into(), code: Some(code.into()), ..RelayFrame::default() };
            match frame_action(&frame) {
                FrameAction::Stop(reason) => assert!(reason.contains(code), "{reason}"),
                other => panic!("{code} produced {other:?} instead of a stop"),
            }
        }
    }

    #[test]
    fn a_resync_error_recovers_instead_of_stopping() {
        let frame = RelayFrame { kind: "error".into(), code: Some("resync_required".into()), ..RelayFrame::default() };
        assert_eq!(frame_action(&frame), FrameAction::Resync);
    }

    #[test]
    fn fenced_epoch_is_a_stop_signal() {
        assert!(relay_error(Some("lease_conflict")).contains("lease_conflict"));
        assert!(relay_error(Some("fenced_epoch")).contains("fenced_epoch"));
    }
