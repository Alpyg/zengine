#

## run

```sh
zig build run
```

## sandbox

```sh
cd sandbox && zig build run
```

## test

```sh
zig build test --summary all
```

## watch

```sh
watchexec -r -e zig -- zig build run
```

## build

```sh
zig build
```

## release

```sh
zig build --release=small
```
