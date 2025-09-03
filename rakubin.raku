#!/usr/bin/env raku

unit sub MAIN(Str  :a(:$address)   = '127.0.0.1',  #= bind to this address
              UInt :p(:$port)      = 9999,         #= bind to this port
              Str  :d(:$directory) is required     #= serve this directory
             );

$directory.IO.mkdir;

given IO::Socket::Async.listen($address, $port) {
    say "[+] Serving $directory on $address:$port";
    .Supply.tap: {
        my $client_address = "{.peer-host}:{.peer-port}";
        say "[+] New client on $client_address";
        my $data = .Supply(:bin).Channel.receive.decode;

        if $data.lines[0] ~~ rx/GET \s (.+) \s 'HTTP/1.1'/ {
            my $filename = $directory.IO.add($0);
            say "[+] $client_address <== $filename";
            .print: "HTTP/1.1 200 OK\r\n\r\n";
            .print: try { $filename.IO.slurp } // "Not found";
        } else {
            my $filename = "{('a'..'z').roll(10).join}{time}";
            $directory.IO.add($filename).spurt($data);
            .say: "http://$address:$port/$filename";
            say "[+] $client_address ==> $filename";
        }
        .close;
    }
}

react {
    whenever signal(SIGINT) {
        say "\rBye !";
        exit;
    }
}
