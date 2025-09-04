#!/usr/bin/env raku

use Log::Async <trace color>;
use Cro::HTTP::Router;
use Cro::HTTP::Server;

sub USAGE {
    print q:c:to/USAGE/;
    Usage:
    {$*PROGRAM-NAME} [options]

    options:
        -a|--address=<Str>           bind to this address [default: '127.0.0.1']
        -p|--port[=UInt]             bind to this port (tcp server) [default: 9999]
        -w|--wport[=UInt]            bind to this port (web server) [default: 4433]
        -d|--directory=<Str>         use this directory to save/serve the pastes
        -m|--max-dir-size[=UInt]     max directory size allowed in byte [default: 100mb]
        -f|--max-file-size[=UInt]    max file size allowed in byte [default: 10mb]
        -t|--timeout[=UInt]          timeout in second to receive a paste [default: 1]
        -k|--pkey-path=<Str>         private key path for tls
        -c|--cert-path=<Str>         certificate path for tls
    USAGE
}

unit sub MAIN(
    Str  :a(:$address)       = '127.0.0.1', #= bind to this address
    UInt :p(:$port)          = 9999,        #= bind to this port (tcp server)
    UInt :w(:$wport)         = 4433,        #= bind to this port (web server)
    Str  :d(:$directory) is required,       #= use this directory to save/serve the pastes
    UInt :m(:$max-dir-size)  = 100_000_000, #= max directory size allowed in byte
    UInt :f(:$max-file-size) = 10_000_000,  #= max file size allowed in byte
    UInt :t(:$timeout)       = 1,           #= timeout in second to receive a paste
    Str  :k(:$pkey-path),                   #= private key path for tls
    Str  :c(:$cert-path),                   #= certificate path for tls
);

##################
# Web Server Setup

my %tls = private-key-file => $pkey-path, certificate-file => $cert-path;
my $is_tls = so ($pkey-path and $cert-path);
debug "is tls: $is_tls";
my $application = route {
    get -> {
       content 'text/html', q:c:to/USAGE/;
        <h3>Send some text and read it back</h3>
        
        <code>
        $ echo just testing! | nc {$address} {$port} </br>
        {$is_tls ?? "https" !! "http" }://{$address}:{$wport}/test </br>
        $ curl {$is_tls ?? "https" !! "http" }://{$address}:{$wport}/test </br>
        just testing! </br>
        </code>
        USAGE
    }

    get -> $id where $directory.IO.add($id).e {
        my $path = $directory.IO.add($id);
        content 'text/plain', $path.slurp;
    }
};

my $web = $is_tls
            ?? Cro::HTTP::Server.new(:host($address), :port($wport), :$application, :%tls)
            !! Cro::HTTP::Server.new(:host($address), :port($wport), :$application);
$web.start;

##################
# Tcp Server Setup

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
            # create a paste
            default {
                my $current-size = run(:out, <<du -b $directory>>).out.slurp.split(/\s/)[0];
                debug "Current size: $current-size/$max-dir-size";
                if $current-size < $max-dir-size {
                    my $filename = "{('a'..'z').roll(10).join}{time}";
                    $directory.IO.add($filename).spurt($data);
                    $client.say: "{$is_tls ?? "https" !! "http" }://$address:$wport/$filename";
                    info "$client_address ==> $filename";
                } else {
                    error "max size reached, please contact SIBL for cleanup";
                    $client.say: "max size reached, please contact SIBL for cleanup";
                }
            }
        }
    }
}

################
# Ctrl-C to Stop

react {
    whenever signal(SIGINT) {
        say "\rBye !";
        $web.stop;
        exit;
    }
}
