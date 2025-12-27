## JavaScriptBridgeWrapper.gd
## Wrapper for JavaScriptBridge singleton methods to enable mocking in unit tests.
##
## Provides instance methods mirroring JavaScriptBridge static methods.
##
## Use this instead of direct JavaScriptBridge calls for testability.

class_name JavaScriptBridgeWrapper

extends RefCounted


func eval(code: String, global_exec: bool = false) -> Variant:
	## Evaluates JavaScript code.
	##
	## Mirrors JavaScriptBridge.eval.
	##
	## :param code: The JavaScript code to evaluate.
	## :type code: String
	## :param global_exec: Whether to execute in global scope.
	## :type global_exec: bool
	## :rtype: Variant
	return JavaScriptBridge.eval(code, global_exec)


func get_interface(interface: String) -> Variant:
	## Gets a JavaScript interface.
	##
	## Mirrors JavaScriptBridge.get_interface.
	##
	## :param interface: The interface name (e.g., "window").
	## :type interface: String
	## :rtype: Variant
	return JavaScriptBridge.get_interface(interface)


func create_callback(callable: Callable) -> Variant:
	## Creates a JavaScript callback from a GDScript callable.
	##
	## Mirrors JavaScriptBridge.create_callback.
	##
	## :param callable: The GDScript callable to wrap.
	## :type callable: Callable
	## :rtype: Variant
	return JavaScriptBridge.create_callback(callable)
