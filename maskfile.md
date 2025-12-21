#

## run

```sh
anyzig build run
```

## demo (demo)

```sh
anyzig build ${demo}-run
```

## test

```sh
anyzig build test --summary all
```

## watch

```sh
watchexec -r -e anyzig -- zig build run
```

## build

```sh
anyzig build
```

## release

```sh
anyzig build --release=small
```
