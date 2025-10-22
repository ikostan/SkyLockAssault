"""List of coordinates for all UI elements in the game."""

# Define element coordinates relative to canvas top-left
UI_ELEMENTS = {
    "start_game_button": {"x": 645, "y": 288},
    "options_button": {"x": 650, "y": 355},
    "quit_button": {"x": 637, "y": 430},
    "difficulty_slider_0.5": {"x": 629, "y": 324},
    "difficulty_slider_1.3": {"x": 686, "y": 324},
    "difficulty_slider_2.0": {"x": 733, "y": 324},
    "back_button": {"x": 655, "y": 450},
    "confirm_dialog_cancel_button": {"x": 659, "y": 429},
    "confirm_dialog_ok_button": {"x": 550, "y": 429},
    "confirm_dialog_x_button": {"x": 659, "y": 428},
    "log_level_combo": {"x": 712, "y": 389},
    "main_menu_button": {"x": 652, "y": 286},
    "resume_button": {"x": 639, "y": 429},
    # Added for log level dropdown
    "log_level_dropdown": {"x": 720, "y": 390},  # Matches log_level_combo, adjust if needed
    "log_level_debug": {"x": 720, "y": 420},    # DEBUG item in dropdown
}
