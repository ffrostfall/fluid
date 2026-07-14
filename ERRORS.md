# Instances

## inst_prop_nonexistent: The property doesn't exist on the given instance.

Self explanatory.

## inst_class_nonexistent: The given instance class doesn't exist.

Self explanatory.

# Cleanup

## cleanup_invalid_scope: Can't call cleanup outside a reactive scope.

Cleanup binds to the destruction of a scope -- you can't use it without a scope.

## cleanup_unknown_destructor: No recognized destructor.

Cleanup takes the following types without trying to find a destructor:

- RbxScriptConnection
- Instance
- Thread
- Function

If it isn't one of these, it'll look for the following methods:

- destroy
- Destroy
- disconnect
- Disconnect

If it cannot find any of these, the error `cleanup_unknown_destructor` will be called.

# Root

## root_already_destroyed: The root was already destroyed

Self explanatory.

## root_fn_error:

Self explanatory.

# Interval

## interval_fn_yielded

## interval_fn_errored

# Reactive Graph

## effect_fn_errored

## effect_fn_yielded

## nil_in_deferred

## recursive_dependency_depeqco

## co_eq_node_state

## dep_state_eq_co

## scope_assertion_failed

## stable_parent_assertion_failed

## invalid_parent_scope
