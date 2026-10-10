// Selects island and nature nicknames and persists the server's accepted name per session id.
// Exports nickname_for_session and accept_session_nickname; depends on private state I/O and ring RNG.

use super::{read_state, write_state};
use ring::rand::{SecureRandom, SystemRandom};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::io;

const NICKNAME: &str = "nickname";
const WORDS: &[&str] = &[
    "otter",
    "coral",
    "reef",
    "gull",
    "tide",
    "palm",
    "lagoon",
    "island",
    "cove",
    "bay",
    "shore",
    "beach",
    "dune",
    "sand",
    "shell",
    "pearl",
    "wave",
    "foam",
    "surf",
    "ocean",
    "sea",
    "kelp",
    "algae",
    "seagrass",
    "mangrove",
    "driftwood",
    "salt",
    "breeze",
    "mist",
    "rain",
    "cloud",
    "sun",
    "moon",
    "star",
    "dawn",
    "dusk",
    "sunrise",
    "sunset",
    "amber",
    "azure",
    "heron",
    "egret",
    "tern",
    "pelican",
    "puffin",
    "osprey",
    "finch",
    "sparrow",
    "robin",
    "lark",
    "wren",
    "swift",
    "swallow",
    "falcon",
    "hawk",
    "eagle",
    "owl",
    "ibis",
    "crane",
    "swan",
    "duck",
    "loon",
    "teal",
    "raven",
    "dove",
    "seal",
    "walrus",
    "dolphin",
    "whale",
    "orca",
    "turtle",
    "gecko",
    "iguana",
    "crab",
    "lobster",
    "shrimp",
    "clam",
    "mussel",
    "oyster",
    "conch",
    "scallop",
    "squid",
    "octopus",
    "nautilus",
    "seahorse",
    "manta",
    "ray",
    "shark",
    "marlin",
    "tuna",
    "salmon",
    "trout",
    "minnow",
    "goby",
    "anchovy",
    "sardine",
    "snapper",
    "grouper",
    "tang",
    "wrasse",
    "fern",
    "moss",
    "lichen",
    "ivy",
    "vine",
    "reed",
    "rush",
    "sedge",
    "bamboo",
    "coconut",
    "papaya",
    "mango",
    "guava",
    "banana",
    "lotus",
    "lily",
    "orchid",
    "hibiscus",
    "jasmine",
    "clover",
    "willow",
    "birch",
    "cedar",
    "pine",
    "spruce",
    "maple",
    "oak",
    "elm",
    "aspen",
    "alder",
    "brook",
    "creek",
    "river",
    "stream",
    "spring",
    "lake",
    "pond",
    "pool",
    "cascade",
    "waterfall",
    "stone",
    "pebble",
    "granite",
    "basalt",
    "quartz",
    "jade",
    "flint",
    "slate",
    "summit",
    "valley",
];

#[derive(Serialize, Deserialize)]
struct StoredNickname {
    id: String,
    nickname: String,
}

fn choose_word() -> io::Result<String> {
    let mut bytes = [0; 8];
    SystemRandom::new()
        .fill(&mut bytes)
        .map_err(|_| io::Error::other("nickname RNG failed"))?;
    let index = (u64::from_le_bytes(bytes) % WORDS.len() as u64) as usize;
    Ok(WORDS[index].to_owned())
}

pub fn nickname_for_session(id: &str) -> io::Result<String> {
    if let Some(stored) = read_state(NICKNAME)
        .and_then(|text| serde_json::from_str::<StoredNickname>(&text).ok())
        .filter(|stored| stored.id == id)
    {
        return Ok(stored.nickname);
    }
    let nickname = choose_word()?;
    store_nickname(id, &nickname)?;
    Ok(nickname)
}

pub fn accept_session_nickname(id: &str, response: &Value) -> io::Result<()> {
    if let Some(nickname) = response.get("nickname").and_then(Value::as_str) {
        store_nickname(id, nickname)?;
    }
    Ok(())
}

fn store_nickname(id: &str, nickname: &str) -> io::Result<()> {
    let stored = StoredNickname {
        id: id.to_owned(),
        nickname: nickname.to_owned(),
    };
    write_state(NICKNAME, &serde_json::to_string(&stored)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn curated_words_are_distinct_lowercase_words_of_the_required_length() {
        let unique: std::collections::HashSet<_> = WORDS.iter().collect();
        assert_eq!(WORDS.len(), 150);
        assert_eq!(unique.len(), WORDS.len());
        assert!(
            WORDS
                .iter()
                .all(|word| (3..=12).contains(&word.len())
                    && word.bytes().all(|byte| byte.is_ascii_lowercase()))
        );
    }

    #[test]
    fn random_choice_is_always_from_the_curated_list() {
        for _ in 0..100 {
            assert!(WORDS.contains(&choose_word().expect("random nickname").as_str()));
        }
    }
}
