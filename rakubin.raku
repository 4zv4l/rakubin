#!/usr/bin/env raku

use Log::Async <trace color>;

sub USAGE {
    print q:c:to/USAGE/;
    Usage:
    {$*PROGRAM-NAME}  [options]

    options:
        -a|--address=<Str>             bind to this address [default: '127.0.0.1']
        -p|--port[=UInt]               bind to this port [default: 9999]
        -d|--directory=<Str>           serve this directory
        -m|--max-dir-size[=UInt]       max directory size allowed in byte [default: 100mb]
        -f|--max-file-size[=UInt]      max file size allowed in byte [default: 10mb]
        -t|--timeout[=UInt]            timeout in second to receive a file [default: 1]
    USAGE
}

unit sub MAIN(Str  :a(:$address)   = '127.0.0.1',       #= bind to this address
              UInt :p(:$port)      = 9999,              #= bind to this port
              Str  :d(:$directory) is required,         #= serve this directory
              UInt :m(:$max-dir-size)  = 100_000_000,   #= max directory size allowed in byte
              UInt :f(:$max-file-size) = 10_000_000,    #= max file size allowed in byte
              UInt :t(:$timeout) = 1,                   #= timeout in second to receive a file
             );

$directory.IO.mkdir;

given IO::Socket::Async.listen($address, $port) {
    info "Serving $directory on $address:$port";
    .Supply.tap: -> $client {
        my $client_address = "{$client.peer-host}:{$client.peer-port}";
        info "New client on $client_address";
        LEAVE $client.close;

        # get client data/request
        my $data = "";
        react {
            whenever $client.Supply(:bin) -> $raw {
                if $data.chars >= $max-file-size {
                    $data = "";
                    fatal "Trying to send too much data !!!";
                    $client.say: "Too much data, try smaller :)";
                    done;
                }
                $data ~= $raw.decode;
            }
            whenever Promise.in($timeout) {
                done
            }
        }

        given $data {
            # empty do nothing
            when .chars == 0 {}
            # get a paste
            when .lines[0] ~~ rx/GET \s (.+) \s 'HTTP/1.1'/ {
                my $filename = $directory.IO.add($0);
                info "$client_address <== $filename";
                $client.print: "HTTP/1.1 200 OK\r\n\r\n";
                $client.print: try { $filename.IO.slurp } // "Not found";
            }
            # create a paste
            default {
                my $current-size = run(:out, <<du -b $directory>>).out.slurp.split(/\s/)[0];
                debug "Current size: $current-size/$max-dir-size";
                if $current-size < $max-dir-size {
                    my $filename = "{('a'..'z').roll(10).join}{time}";
                    $directory.IO.add($filename).spurt($data);
                    $client.say: "http://$address:$port/$filename";
                    info "$client_address ==> $filename";
                } else {
                    error "max size reached, please contact SIBL for cleanup";
                    $client.say: "max size reached, please contact SIBL for cleanup";
                }
            }
        }
    }
}

react {
    whenever signal(SIGINT) {
        say "\rBye !";
        exit;
    }
}
