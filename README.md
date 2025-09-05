# Rakubin

Simple [termbin](https://github.com/insomnimus/termbin) in Raku, lets you create paste from the command line.

## Usage

You can use the `-h` or `--help` to show this help:

```
Usage:
pastebin.raku [options]

options:
    -a|--address=<Str>           bind to this address [default: '127.0.0.1']
    -u|--url=<Str>               uses this url when generating links
    -p|--tcp-port[=UInt]         bind to this port (tcp server) [default: 9999]
    -w|--web-port[=UInt]         bind to this port (web server) [default: 4433]
    -d|--directory=<Str>         directory to save/serve the pastes [mendatory]
    -m|--max-dir-size[=UInt]     max directory size allowed in byte [default: 100mb]
    -f|--max-file-size[=UInt]    max file size allowed in byte [default: 10mb]
    -t|--timeout[=UInt]          timeout in second to receive a paste [default: 1]
    -k|--pkey-path=<Str>         private key path for tls
    -c|--cert-path=<Str>         certificate path for tls
    -l|--logfile=<Str>           use that file for logging
    -v|--loglevel=<Loglevels>    log message up to that level [default: DEBUG]
    -r|--randlen[=UInt]          IDs length (may take time to generate) [default: 4]
    -g|--gc                      delete old paste if the pool is full [default: False]
```

Loglevels: `TRACE`, `DEBUG`, `INFO`, `WARNING`, `ERROR`, `FATAL`.

## Example

```bash
# start rakubin server
rakubin.raku -d tmp

# create a paste
echo foobar | nc localhost 9999
http://127.0.0.1:4433/a4bz

# access the paste
curl http://127.0.0.1:4433/a4bz
foobar
```

You can stop the server at anytime using `ctrl-c`.

> You can use custom IDs for the paste by pre-creating files
> in the $directory since the garbage collector will reuse found file
> when there are no more IDs available.
