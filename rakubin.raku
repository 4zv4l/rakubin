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
        -p|--tcp-port[=UInt]         bind to this port (tcp server) [default: 9999]
        -w|--web-port[=UInt]         bind to this port (web server) [default: 4433]
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
    UInt :p(:$tcp-port)      = 9999,        #= bind to this port (tcp server)
    UInt :w(:$web-port)      = 4433,        #= bind to this port (web server)
    Str  :d(:$directory) is required,       #= use this directory to save/serve the pastes
    UInt :m(:$max-dir-size)  = 100_000_000, #= max directory size allowed in byte
    UInt :f(:$max-file-size) = 10_000_000,  #= max file size allowed in byte
    UInt :t(:$timeout)       = 1,           #= timeout in second to receive a paste
    Str  :k(:$pkey-path),                   #= private key path for tls
    Str  :c(:$cert-path),                   #= certificate path for tls
);

my $is_tls    = so ($pkey-path and $cert-path);
my $show_port = !so (($web-port == 80 and !$is_tls) or ($web-port == 443 and $is_tls));
my $web_url   = "{$is_tls ?? "https" !! "http" }://{$address}{":" ~ $web-port if $show_port}";
debug "is_tls: $is_tls";
debug "show_port: $show_port";
debug "web_url: $web_url";

##################
# Web Server Setup

my %tls = private-key-file => $pkey-path, certificate-file => $cert-path;
my $application = route {
    get -> {
       content 'text/html', q:c:to/USAGE/;
        <h3>Send some text and read it back</h3>
        
        <code>
        $ echo just testing! | nc {$address} {$tcp-port} </br>
        {$web_url}/test </br>
        $ curl {$web_url}/test </br>
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
            ?? Cro::HTTP::Server.new(:host($address), :port($web-port), :$application, :%tls)
            !! Cro::HTTP::Server.new(:host($address), :port($web-port), :$application);
$web.start;

##################
# Tcp Server Setup

$directory.IO.mkdir;

given IO::Socket::Async.listen($address, $tcp-port) {
    info "Serving $directory on $address:$tcp-port";
    .Supply.tap: -> $client {
        my $client_address = "{$client.peer-host}:{$client.peer-port}";
        info "New client on $client_address";
        LEAVE $client.close;

        # get client paste
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
                    $client.say: "web_url/$filename";
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
