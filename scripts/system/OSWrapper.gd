## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## OSWrapper.gd
## Wrapper for OS singleton methods to enable mocking in unit tests.
##
## Provides instance methods mirroring OS static methods.
##
## Use this instead of direct OS calls for testability.

class_name OSWrapper

extends RefCounted


func has_feature(feature: String) -> bool:
	## Checks if the current platform has a specific feature.
	##
	## Mirrors OS.has_feature.
	##
	## :param feature: The feature name to check (e.g., "web").
	## :type feature: String
	## :rtype: bool
	return OS.has_feature(feature)
