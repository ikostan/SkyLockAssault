# Eliminate arbitrary synchronization delays in Integration & CI tests
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

By tracking the HTTP server `GET /index.html` request deltas, we can observe the exact execution window and duration of each browser test:

## ⏱️ Individual Test Execution Breakdown

| Test File                                                   | Start Time | End Time   | Approx. Duration |
|-------------------------------------------------------------|------------|------------|------------------|
| `tests/audio_flow_test.py`                                  | `19:16:01` | `19:16:06` | ~5.0s            |
| `tests/back_flow_test.py` *(includes 1 page reload)*        | `19:16:06` | `19:16:15` | ~9.0s            |
| `tests/difficulty_flow_test.py`                             | `19:16:15` | `19:16:24` | ~9.0s            |
| `tests/difficulty_integration_test.py`                      | `19:16:24` | `19:16:32` | ~8.0s            |
| `tests/fuel_depletion_test.py`                              | `19:16:32` | `19:16:49` | ~17.0s           |
| `tests/load_main_menu_test.py`                              | `19:16:49` | `19:16:51` | ~2.0s            |
| `tests/log_level_test.py`                                   | `19:16:51` | `19:16:55` | ~4.0s            |
| `tests/navigation_to_audio_test.py`                         | `19:16:55` | `19:17:00` | ~5.0s            |
| `tests/no_error_logs_test.py`                               | `19:17:00` | `19:17:02` | ~2.0s            |
| `tests/reset_audio_flow_test.py` *(includes 1 page reload)* | `19:17:02` | `19:17:12` | ~10.0s           |
| `tests/validate_clean_load_test.py`                         | `19:17:12` | `19:17:14` | ~2.0s            |
| `tests/volume_sliders_mutes_test.py`                        | `19:17:14` | `19:17:20` | ~6.0s            |
| `tests/weapon_firing_test.py`                               | `19:17:20` | `19:17:28` | ~8.0s            |

---

### Key Execution Highlights

* **Total Suite Duration:** **87.91 seconds** (13 passed, 0 failed).
* **Longest Test:** `tests/fuel_depletion_test.py` (~17.0s) due to waiting for dynamic fuel consumption ticks.
* **Fastest Tests:** `load_main_menu_test.py`, `no_error_logs_test.py`, and `validate_clean_load_test.py` (~2.0s each) which evaluate immediately upon engine initialization.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
