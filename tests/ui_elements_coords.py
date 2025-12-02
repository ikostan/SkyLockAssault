"""List of coordinates for all UI elements in the game."""

# tests/ui_elements_coords.py

# Define element coordinates relative to canvas top-left
UI_ELEMENTS = {
    "start_game_button": {"x": 645, "y": 288},
    "options_button": {"x": 635, "y": 355},
    "quit_button": {"x": 637, "y": 430},
    "difficulty_slider_0.5": {"x": 630, "y": 160},
    "difficulty_slider_1.3": {"x": 686, "y": 160},
    "difficulty_slider_2.0": {"x": 733, "y": 160},
    "back_button": {"x": 647, "y": 625},
    "confirm_dialog_cancel_button": {"x": 659, "y": 429},
    "confirm_dialog_ok_button": {"x": 550, "y": 429},
    "confirm_dialog_x_button": {"x": 659, "y": 428},
    "main_menu_button": {"x": 652, "y": 286},
    "resume_button": {"x": 639, "y": 429},
    # Added for log level dropdown
    "log_level_dropdown": {"x": 705, "y": 285},  # Matches log_level_combo, adjust if needed
    "log_level_debug": {"x": 705, "y": 315},    # DEBUG item in dropdown
}
