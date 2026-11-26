//! The hold-to-talk gesture — DictationHoldGesture.swift, line for line, and
//! held to the same specification: tests/fixtures/dictation.json's "hold".
//!
//! A state machine with no clock and no keyboard: dictation_keys.rs feeds it
//! what the key did and when (and a tick at the minimum hold and at the cap),
//! and it answers with what to do. Pure, so it is tested anywhere.

use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Input {
    Down,
    Up,
    Other,
    Escape,
    Tick,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Action {
    Arm,
    Show,
    Commit,
    Cancel,
}

pub const MINIMUM_HOLD_MS: u64 = 300;
pub const MAXIMUM_HOLD_MS: u64 = 300_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
enum Hold {
    #[default]
    Idle,
    Armed(u64),
    Shown(u64),
    /// Committed at the cap or cancelled: the key is still down, and its
    /// release must not start anything.
    WaitingForRelease,
}

/// tests/fixtures/dictation.json's "hold" section is this machine's
/// specification — and the Mac's.
#[derive(Default)]
pub struct HoldGesture {
    state: Hold,
}

impl HoldGesture {
    pub fn handle(&mut self, input: Input, at_ms: u64) -> Vec<Action> {
        use Action::*;
        match (self.state, input) {
            (Hold::Idle, Input::Down) => {
                self.state = Hold::Armed(at_ms);
                vec![Arm]
            }
            (Hold::Idle, _) => vec![],

            (Hold::Armed(since), Input::Tick) => {
                if at_ms.saturating_sub(since) < MINIMUM_HOLD_MS {
                    return vec![];
                }
                self.state = Hold::Shown(since);
                let mut actions = vec![Show];
                actions.extend(self.cap(since, at_ms));
                actions
            }
            (Hold::Armed(since), Input::Up) => {
                self.state = Hold::Idle;
                if at_ms.saturating_sub(since) >= MINIMUM_HOLD_MS { vec![Show, Commit] } else { vec![Cancel] }
            }
            (Hold::Armed(_), Input::Other | Input::Escape) => {
                self.state = Hold::WaitingForRelease;
                vec![Cancel]
            }
            (Hold::Armed(_), Input::Down) => vec![], // key repeat

            (Hold::Shown(since), Input::Tick) => self.cap(since, at_ms),
            (Hold::Shown(_), Input::Up) => {
                self.state = Hold::Idle;
                vec![Commit]
            }
            (Hold::Shown(_), Input::Other | Input::Escape) => {
                self.state = Hold::WaitingForRelease;
                vec![Cancel]
            }
            (Hold::Shown(_), Input::Down) => vec![],

            (Hold::WaitingForRelease, Input::Up) => {
                self.state = Hold::Idle;
                vec![]
            }
            (Hold::WaitingForRelease, _) => vec![],
        }
    }

    fn cap(&mut self, since: u64, at_ms: u64) -> Vec<Action> {
        if at_ms.saturating_sub(since) < MAXIMUM_HOLD_MS {
            return vec![];
        }
        self.state = Hold::WaitingForRelease;
        vec![Action::Commit]
    }

    pub fn is_holding(&self) -> bool {
        matches!(self.state, Hold::Armed(_) | Hold::Shown(_))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    const FIXTURE: &str = include_str!("../../../tests/fixtures/dictation.json");

    fn hold() -> Value {
        serde_json::from_str::<Value>(FIXTURE).expect("tests/fixtures/dictation.json parses")["hold"].clone()
    }

    #[test]
    fn the_limits_are_the_macs() {
        let hold = hold();
        assert_eq!(hold["minimumHoldMs"].as_u64(), Some(MINIMUM_HOLD_MS));
        assert_eq!(hold["maximumHoldMs"].as_u64(), Some(MAXIMUM_HOLD_MS));
    }

    #[test]
    fn the_gesture_follows_the_fixture() {
        let cases = hold()["cases"].as_array().expect("hold cases").clone();
        assert!(!cases.is_empty());
        let mut wrong = Vec::new();
        for case in cases {
            let name = case["name"].as_str().unwrap_or("?").to_string();
            let mut gesture = HoldGesture::default();
            let mut actions: Vec<String> = Vec::new();
            for event in case["events"].as_array().expect("events") {
                let kind = event[0].as_str().expect("event kind");
                let at = event[1].as_u64().expect("event time");
                let input = match kind {
                    "down" => Input::Down,
                    "up" => Input::Up,
                    "other" => Input::Other,
                    "escape" => Input::Escape,
                    "tick" => Input::Tick,
                    other => panic!("unknown event {other}"),
                };
                for action in gesture.handle(input, at) {
                    actions.push(serde_json::to_value(action).unwrap().as_str().unwrap().to_string());
                }
            }
            let want: Vec<String> = case["actions"]
                .as_array()
                .expect("actions")
                .iter()
                .map(|a| a.as_str().unwrap().to_string())
                .collect();
            if actions != want {
                wrong.push(format!("{name}: got {actions:?}, want {want:?}"));
            }
        }
        assert!(wrong.is_empty(), "the hold gesture disagrees with the fixture:\n  {}", wrong.join("\n  "));
    }
}
