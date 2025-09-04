#!/usr/bin/env raku

use Log::Async <trace color>;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
use Number::Bytes::Human :functions;

sub USAGE {
    print q:c:to/USAGE/;
    Usage:
    {$*PROGRAM-NAME} [options]

    options:
        -a|--address=<Str>           bind to this address [default: '127.0.0.1']
        -u|--url=<Str>               uses this url when generating links
        -p|--tcp-port[=UInt]         bind to this port (tcp server) [default: 9999]
        -w|--web-port[=UInt]         bind to this port (web server) [default: 4433]
        -d|--directory=<Str>         use this directory to save/serve the pastes
        -m|--max-dir-size[=UInt]     max directory size allowed in byte [default: 100mb]
        -f|--max-file-size[=UInt]    max file size allowed in byte [default: 10mb]
        -t|--timeout[=UInt]          timeout in second to receive a paste [default: 1]
        -k|--pkey-path=<Str>         private key path for tls
        -c|--cert-path=<Str>         certificate path for tls
        -l|--logfile=<Str>           use that file for logging
        -v|--loglevel=<Loglevels>    log message up to that level [default: DEBUG]
        -r|--randlen[=UInt]          IDs length (may take time to generate) [default: 4]
        -g|--gc                      Delete old paste if the pool is full [default: False]
    USAGE
}

unit sub MAIN(
    Str        :a(:$address)       = '127.0.0.1', #= bind to this address
    Str        :u(:$url)           = $address,    #= uses this url when generating links
    UInt       :p(:$tcp-port)      = 9999,        #= bind to this port (tcp server)
    UInt       :w(:$web-port)      = 4433,        #= bind to this port (web server)
    Str        :d(:$directory) is required,       #= use this directory to save/serve the pastes
    UInt       :m(:$max-dir-size)  = 104_857_600, #= max directory size allowed in byte
    UInt       :f(:$max-file-size) = 10_485_760,  #= max file size allowed in byte
    UInt       :t(:$timeout)       = 1,           #= timeout in second to receive a paste
    Str        :k(:$pkey-path),                   #= private key path for tls
    Str        :c(:$cert-path),                   #= certificate path for tls
    Str        :l(:$logfile),                     #= use that file for logging
    Loglevels  :v(:$loglevel)      = DEBUG,       #= log message up to that level
    UInt       :r(:$randlen)       = 4,           #= IDs length (may take time to generate)
    Bool       :g(:$gc)            = False,       #= Delete old paste if the pool is full
);

#####################
# Basic Var/Log Setup

info "Generating IDs...";
my @IDs       = $randlen ?? ('a'..'z',0..9).flat.combinations($randlen).pick(*) !! ();
my $is_tls    = so ($pkey-path and $cert-path);
my $show_port = !so (($web-port == 80 and !$is_tls) or ($web-port == 443 and $is_tls));
my $web_url   = "{$is_tls ?? "https" !! "http" }://{$url}{":" ~ $web-port if $show_port}";
logger.send-to($logfile, :level(* >= $loglevel)) if $logfile;
debug "IDS: {@IDs.elems} available";
debug "logging up to $loglevel at $logfile" if $logfile;
debug "is_tls: $is_tls";
debug "show_port: $show_port";
debug "web_url: $web_url";
debug "gc: $gc";

##################
# Web Server Setup

my %tls = private-key-file => $pkey-path, certificate-file => $cert-path;
my $application = route {
    get -> {
       content 'text/html', q:c:to/USAGE/;
        <h3>Send some text and read it back</h3>
        
        <code>
        $ echo just testing! | nc {$url} {$tcp-port} </br>
        {$web_url}/test </br>
        $ curl {$web_url}/test </br>
        just testing! </br>
        </code>
        USAGE
    }

    get -> $id where $directory.IO.add($id).e {
        my @caddr = request.connection.map({.peer-host, .peer-port}).first;
        info "{@caddr.join(':')} <== $id";
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
                #gc IDs
                my $remaining-IDs = @IDs.elems;
                debug "Remaining IDs: {@IDs.elems}";
                if $remaining-IDs == 0 and $gc {
                    warning "No more IDs, gc is on !";
                    @IDs = $directory.IO.dir(test => { "$directory/$_".IO.f }).sort({.created}).map({.basename});
                    error "Couldnt free any paste" unless @IDs;
                }

                # gc free disk space
                my $current-size = $directory.IO.dir.map({.s}).sum;
                debug "Current size: {format-bytes +$current-size}/{format-bytes +$max-dir-size}";
                if $current-size > $max-dir-size and $gc {
                    warning "No more space, gc is on !";
                    while $current-size > $max-dir-size {
                        my $to-del = $directory.IO.dir(test => { "$directory/$_".IO.f }).sort({.created}).head;
                        if $to-del {
                            warning "Deleting $to-del";
                            $current-size -= $to-del.IO.s;
                            unlink $to-del;
                            push @IDs, $to-del.basename;
                        } else {
                            fatal "Couldnt free any paste";
                        }
                    }
                }

                if $current-size < $max-dir-size and @IDs.elems {
                    my $filename = @IDs.pop.join;
                    $directory.IO.add($filename).spurt($data);
                    $client.say: "$web_url/$filename";
                    info "$client_address ==> $filename";
                } else {
                    fatal "paste pool is full !!!";
                    $client.say: "the paste pool is full, please contact the admin for cleanup";
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
