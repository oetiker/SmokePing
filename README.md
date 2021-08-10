```
____                  _        ____  _             
/ ___| _ __ ___   ___ | | _____|  _ \(_)_ __   __ _ 
\___ \| '_ ` _ \ / _ \| |/ / _ \ |_) | | '_ \ / _` |
 ___) | | | | | | (_) |   <  __/  __/| | | | | (_| |
|____/|_| |_| |_|\___/|_|\_\___|_|   |_|_| |_|\__, |
                                              |___/ 
```

Original Authors:  Tobias Oetiker <tobi of oetiker.ch> and Niko Tyni <ntyni with iki.fi>

[![Build Test](https://github.com/oetiker/SmokePing/actions/workflows/build-test.yaml/badge.svg)](https://github.com/oetiker/SmokePing/actions/workflows/build-test.yaml)

SmokePing is a latency logging and graphing and
alerting system. It consists of a daemon process which
organizes the latency measurements and a CGI which
presents the graphs.

SmokePing is ...
================

 * extensible through plug-in modules

 * easy to customize through a webtemplate and an extensive
   configuration file.

 * written in perl and should readily port to any unix system

 * an RRDtool frontend

 * able to deal with DYNAMIC IP addresses as used with
   Cable and ADSL internet.


cheers
tobi
