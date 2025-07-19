export type Readable<T> = () -> T
export type Callable<T> = (value: T) -> ()

export type Effect<T> = (value: T) -> T

export type Source<T> = ((T) -> T) & Readable<T>

export type UsedAs<T> = T | Readable<T>

export type Cleanup = () -> ()

return nil
