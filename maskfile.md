#

## run

```sh
zig build run
```

## demo (demo)

```sh
zig build ${demo}-run
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
