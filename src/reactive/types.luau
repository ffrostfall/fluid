export type Readable<T> = () -> T
export type Callable<T> = (value: T) -> ()

export type Effect<T> = (value: T) -> T

-- somewhat misleading but will never produce invalid calls and has
-- less false positive type errors
export type Source<T> = (...T) -> T

export type UsedAs<T> = T | Readable<T>

export type Cleanup = () -> ()

return nil
