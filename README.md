# lager_sendmail_backend

## overwiev

backend for erlang basho lager (https://github.com/basho/lager) that sends letters thru sendmail


## install using rebar

add

`{lager_sendmail_backend, ".*", {git, "https://github.com/enotsimon/lager_sendmail_backend.git", {branch, "master"}}}`

to your `rebar.config` file in your erlang app


## usage

add to your app config files something like this

```
{lager, [
    {handlers, [
        {lager_sendmail_backend, [
            {level, error},
            {from, "lager_sendmail_backend <from@example.com>"},
            {to, ["errors@example.com"]},
            {subject, "erlang errors in my app"},
            {aggregate_interval, 60000}, % aggregate messages every 1 min. thats default
            {msg_limit, 20}, % messages per letter. thats default
            {sendmail_cmd, "/usr/sbin/sendmail -t"} % cmd to send email. thats default. use "cat > bla" for debug
        ]},
        {lager_sendmail_backend, [
            {level, warning},
            {from, "lager_sendmail_backend <from@example.com>"},
            {to, ["warnings@example.com"]},
            {subject, "erlang warnings in my app"}
        ]}
    ]}
]}
```
unfortunately, you cannot use one instance of backend for both warnings and errors for now...
