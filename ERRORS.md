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

## root_user_errored:

Self explanatory.

# Interval

## interval_user_yielded

## interval_user_errored

# Reactive Graph

## effect_errored

## effect_yielded

## nil_in_deferred

The internal graph r
