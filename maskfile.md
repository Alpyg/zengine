#

## run

```sh
anyzig build run
```

## demo (demo)

```sh
anyzig build ${demo}-run --release=fast
```

## test

```sh
anyzig build test --summary all
```

## watch

```sh
watchexec -c -r -e zig -- anyzig build sandbox-run
```

## build

```sh
anyzig build
```

## release

```sh
anyzig build --release=small
```
