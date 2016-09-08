-module(lager_sendmail_backend).
-behaviour(gen_event).
-include_lib("lager/include/lager.hrl").

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2, code_change/3]).

-define(DEFAULT_AGGREGATE_INTERVAL, 600000).
-define(MSG_LIMIT, 20).

-record(state,{
		uid :: {integer(), integer(), integer()},
		from :: binary(),
		to :: [binary()],
		subject :: binary(),
		level :: integer(),
		msg_limit :: integer(),
		timer = void :: reference()|'void',
		aggregate_interval :: integer(),
		messages = [] :: list(),
		msg_count = 0 :: integer(),
		sendmail_cmd :: list()
	}).

init(Config) ->
	{ok, #state{
			uid = os:timestamp(),
			from = list_to_binary(proplists:get_value(from, Config)),
			to = [list_to_binary(E) || E <- proplists:get_value(to, Config)],
			subject = list_to_binary(proplists:get_value(subject, Config)),
			level = lager_util:level_to_num(proplists:get_value(level, Config)),
			msg_limit = proplists:get_value(msg_limit, Config, ?MSG_LIMIT),
			aggregate_interval = proplists:get_value(aggregate_interval, Config, ?DEFAULT_AGGREGATE_INTERVAL),
			sendmail_cmd = proplists:get_value(sendmail_cmd, Config, "/usr/sbin/sendmail -t")
		}}.


terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

handle_call(get_loglevel, #state{level = LogLevel} = State) ->
	{ok, LogLevel, State};

handle_call({set_loglevel, LogLevel}, State) ->
	case lists:member(LogLevel, ?LEVELS) of
		true ->
			{ok, ok, State#state{level = lager_util:level_to_num(LogLevel)}};
		_ ->
			{ok, {error, bad_log_level}, State}
	end;

handle_call(V, State) -> {stop, {unexpected_call, V}, State}.




handle_event({log, Message}, State) ->
	SeverityAsInt = lager_msg:severity_as_int(Message),
	NewState = handle_log(Message, SeverityAsInt, State),
	{ok, NewState};

handle_event(V, State) ->
	{stop, {unexpected_event, V}, State}.


% message from port after closing
handle_info({'EXIT', _Port, _Reason}, State) ->
	{ok, State};

handle_info({flush_aggregated, MUid}, #state{uid = Uid} = State) when MUid =:= Uid ->
	#state{msg_count = MsgCount, msg_limit = MsgLimit} = State,
	erlang:cancel_timer(State#state.timer),
	DDD = case MsgCount > MsgLimit of
		true ->
			CountOfMsgs = unicode:characters_to_binary(io_lib:format("~p of ~p messages:\n\n", [MsgLimit, MsgCount])),
			[CountOfMsgs | lists:reverse(State#state.messages)];
		false ->
			lists:reverse(State#state.messages)
	end,
	Data = << << LetterText/binary, "\n\n" >> || LetterText <- DDD >>,
	To = << <<" ", E/binary>> || E <- State#state.to >>,
	SendmailCmd = State#state.sendmail_cmd,
	send(To, State#state.from, State#state.subject, Data, SendmailCmd),
	{ok, State#state{timer = void, msg_count = 0, messages = []}};

% not our 'flush_aggregated' message
handle_info({flush_aggregated, _MUid}, State) ->
	{ok, State};

% ignore log rotate events
handle_info({rotate, _LogFile}, State) ->
	{ok, State};

handle_info(V, State) -> {stop, {unexpected_info, V}, State}.



%%
%% PRIVATE
%%
handle_log(_Message, SeverityAsInt, #state{level = Level, msg_count = MsgCount, msg_limit = MsgLimit} = State) when (SeverityAsInt =:= Level) and (MsgCount > MsgLimit) ->
	State#state{msg_count = MsgCount+1};

handle_log(Message, SeverityAsInt, #state{level = Level} = State) when SeverityAsInt =:= Level ->
	Msg = lager_msg:message(Message),
	%Timestamp = lager_msg:timestamp(Message),
	{Date, Time} = lager_msg:datetime(Message),
	Severity = lager_msg:severity(Message),
	Metadata = lager_msg:metadata(Message),
	{ok, Host} = inet:gethostname(),
	Format = "~s ~s ~p\nmessage: ~ts\nmeta: ~p\nhost: ~p",
	LetterText = unicode:characters_to_binary(io_lib:format(Format, [Date, Time, Severity, Msg, Metadata, Host])),
	#state{messages = Messages, msg_count = MsgCount} = State,
	install_new_timer(State#state{msg_count = MsgCount + 1, messages = [LetterText | Messages]});

handle_log(_Message, _SeverityAsInt, State) ->
	State.


install_new_timer(#state{timer = void, aggregate_interval = Interval, uid = Uid} = State) ->
	State#state{timer = erlang:send_after(Interval, self(), {flush_aggregated, Uid})};
install_new_timer(State) -> State.



send(To, From, Subject, Message, SendmailCmd) ->
	Letter = <<
		"To: ", To/binary, "\r\n",
		"MIME-Version: 1.0\r\n",
		"Content-type: text/plain; charset=utf-8\r\n",
		"Content-transfer-encoding: binary\r\n",
		"From: ", From/binary,"\r\n",
		"Subject: =?utf-8?B?", (base64:encode(Subject))/binary, "?=\r\n",
		"\r\n",
		Message/binary,
		"\r\n.\r\n"
	>>,
	Port = open_port({spawn, SendmailCmd}, [binary]),
	Port ! {self(), {command, Letter}},
	port_close(Port).


