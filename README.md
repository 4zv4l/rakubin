# rakubin

simple termbin in Raku

# usage

You can use the `-h` or `--help` to show this help:

```
Usage:
pastebin.raku [options]

options:
    -a|--address=<Str>           bind to this address [default: '127.0.0.1']
    -p|--port[=UInt]             bind to this port [default: 9999]
    -d|--directory=<Str>         serve this directory
    -m|--max-dir-size[=UInt]     max directory size allowed in byte [default: 100mb]
    -f|--max-file-size[=UInt]    max file size allowed in byte [default: 10mb]
    -t|--timeout[=UInt]          timeout in second to receive a file [default: 1]
```

Basic usage:

```bash
# start rakubin server
rakubin.raku -d tmp

# create a paste
cat rakubin.raku | nc localhost 9999
> http://127.0.0.1:9999/ovxmsjectt1756871999

# access the paste
curl http://127.0.0.1:9999/ovxmsjectt1756871999
...
```

You can stop the server at anytime using `ctrl-c`.
