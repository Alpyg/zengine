#

## run

```sh
zig build run
```

## demo (demo)

```sh
zig build ${demo}-run --release=fast
```

## test

```sh
zig build test --summary all
```

## watch

```sh
watchexec -c -r -e zig -- zig build sandbox-run
```

## build

```sh
zig build
```

## release

```sh
zig build --release=small
```
