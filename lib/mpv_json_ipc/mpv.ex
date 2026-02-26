defmodule MpvJsonIpc.Mpv do
  @moduledoc """
  Main module to interract with an MPV instance.
  """
  use GenServer, restart: :transient
  require Logger

  alias MpvJsonIpc.Connection

  @doc false
  def name(seed), do: Connection.via(__MODULE__, seed)

  @doc false
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: name(opts[:seed]))

  @doc """
  Sends the command to the MPV instance.

  Available commands are [here](https://mpv.io/manual/master/#list-of-input-commands).

  ## Examples
      MpvJsonIpc.Mpv.command(server, "get_property", "playback-time")
      MpvJsonIpc.Mpv.command(server, :get_property, :"playback-time")
      MpvJsonIpc.Mpv.command(main, "expand-properties", ["print-text", "${playback-time}"])
      MpvJsonIpc.Mpv.command(server, :set_property, [:pause, true])
      MpvJsonIpc.Mpv.command(server, %{
        name: "loadfile",
        url:
          "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        options: %{
          cache: "yes",
          "demuxer-max-bytes": "100MiB",
          "demuxer-max-back-bytes": "100MiB"
        }
      })
  """
  def command(server, cmd, args \\ [])

  def command(server, cmd, _args) when is_map(cmd),
    do:
      GenServer.call(
        server,
        {:command, %{command: cmd}},
        timeout()
      )

  def command(server, name, args) when (is_binary(name) or is_atom(name)) and is_list(args),
    do:
      GenServer.call(
        server,
        {:command,
         %{
           command: [name] ++ args
         }},
        timeout()
      )

  def command(server, name, arg)
      when (is_binary(name) or is_atom(name)) and (is_binary(arg) or is_atom(arg)),
      do: command(server, name, [arg])

  @impl true
  def init(opts) do
    {%{request_id: request_id, observer_id: observer_id, keybind_id: keybind_id}, opts} =
      Connection.connect(opts)

    {:ok,
     {%{request_id: request_id, observer_id: observer_id, keybind_id: keybind_id}, opts[:seed]},
     {:continue, {:logs, opts[:log_level], opts[:log_handler]}}}
  end

  @impl true
  def handle_continue({:logs, log_level, log_handler}, {state, seed}) do
    new_state = Connection.log_setup({log_level, log_handler}, {state, seed})
    {:noreply, {new_state, seed}}
  end

  @impl true
  def handle_call({:command, cmd}, _from, {state, seed}) do
    {reply, new_state} = Connection.command(cmd, state, seed)
    {:reply, reply, {new_state, seed}}
  end

  @impl true
  def handle_call({:bind_event, event, callback}, _from, {_state, seed} = s) do
    :ok = MpvJsonIpc.Event.name(seed) |> MpvJsonIpc.Event.add_event_callback(event, callback)
    {:reply, :ok, s}
  end

  @impl true
  def handle_call({:bind_key, name, callback}, _from, {state, seed}) do
    bind_name = "bind#{state[:keybind_id]}"
    :ok = MpvJsonIpc.Event.name(seed) |> MpvJsonIpc.Event.add_keybinding(bind_name, callback)
    cmd = %{command: [:keybind, name, "script-message custom-bind #{bind_name}"]}
    {reply, new_state} = Connection.command(cmd, state, seed)
    new_state = new_state |> Map.update!(:keybind_id, &(&1 + 1))
    {:reply, reply, {new_state, seed}}
  end

  @impl true
  def handle_call({:observe_property, name, callback}, _from, {state, seed}) do
    :ok =
      MpvJsonIpc.Event.name(seed)
      |> MpvJsonIpc.Event.add_property_callback(state[:observer_id], callback)

    cmd = %{command: [:observe_property, state[:observer_id], name]}
    {:ok, new_state} = Connection.command(cmd, state, seed)
    new_state = new_state |> Map.update!(:observer_id, &(&1 + 1))
    {:reply, state[:observer_id], {new_state, seed}}
  end

  @impl true
  def handle_call({:unobserve_property, del_observer_id}, _from, {state, seed}) do
    :ok =
      MpvJsonIpc.Event.name(seed) |> MpvJsonIpc.Event.remove_property_callback(del_observer_id)

    cmd = %{command: [:unobserve_property, del_observer_id]}
    {reply, new_state} = Connection.command(cmd, state, seed)
    {:reply, reply, {new_state, seed}}
  end

  @impl true
  def handle_info({_port, {:exit_status, _}}, {state, seed}) do
    Task.start(fn -> :ok = MpvJsonIpc.Mpv.Sup.stop(seed) end)
    {:stop, :normal, {state, seed}}
  end

  for {macro, func} <- [
        {%{
           doc: """
           Convenience to register a `callback` for the event `name`.

           ## Examples
               MpvJsonIpc.Mpv.on_event server, "seek" do
                 IO.inspect("seeking")
               end
           """,
           name: :on_event
         },
         %{
           doc: ~S"""
           Registers a `callback` to call when the event `name` occurs.

           ## Examples
               MpvJsonIpc.Mpv.bind_event(server, "seek", fn _ -> IO.inspect("seeking") end)
               MpvJsonIpc.Mpv.bind_event(server, "end-file", fn data -> IO.inspect("end-file with reason #{data[:reason]}") end)
           """,
           name: :bind_event
         }},
        {%{
           doc: """
           Convenience to register a `callback` for the key `name`.

           ## Examples
               MpvJsonIpc.Mpv.on_keypress server, "g" do
                 IO.inspect("key g is pressed")
               end
           """,
           name: :on_keypress
         },
         %{
           doc: """
           Registers a `callback` to call when the key `name` is pressed.

           ## Examples
               MpvJsonIpc.Mpv.bind_key(server, "g", fn _ -> IO.inspect("key g is pressed") end)
           """,
           name: :bind_key
         }},
        {%{
           doc: """
           Convenience to register a `callback` for the property `name`.

           ## Examples
               MpvJsonIpc.Mpv.property_observer server, "pause" do
                 if pause, do: IO.inspect("in pause"), else: IO.inspect("playing")
               end
           """,
           name: :property_observer
         },
         %{
           doc: ~S"""
           Registers a `callback` to call when the property `name` changes.

           ## Examples
               MpvJsonIpc.Mpv.observe_property(server, "pause", fn pause -> IO.inspect("Property pause now has value #{pause}") end)
           """,
           name: :observe_property
         }}
      ] do
    @doc func.doc
    def unquote(func.name)(server, name, callback) when is_function(callback, 1),
      do:
        GenServer.call(
          server,
          {unquote(func.name), name, callback},
          timeout()
        )

    @doc macro.doc
    defmacro unquote(macro.name)(server, name, do: body) do
      arg = Macro.var(String.to_atom(name), __MODULE__)

      callback =
        if unquote(func.name) == :observe_property do
          quote do
            fn var!(unquote(arg)) ->
              unquote(body)
            end
          end
        else
          quote do
            fn var!(data) ->
              _ = var!(data)
              unquote(body)
            end
          end
        end

      quote bind_quoted: [
              server: server,
              name: name,
              callback: callback,
              func: unquote(func.name),
              module: __MODULE__
            ] do
        apply(module, func, [server, name, callback])
      end
    end
  end

  @doc ~S"""
  Deletes a property observer with given `observer_id`.

  ## Examples
      oid = MpvJsonIpc.Mpv.observe_property(server, "pause", fn pause -> IO.inspect("Property pause now has value #{pause}") end)
      ...
      MpvJsonIpc.Mpv.unobserve_property(server, oid)
  """
  def unobserve_property(server, observer_id),
    do:
      GenServer.call(
        server,
        {:unobserve_property, observer_id},
        timeout()
      )

  defp timeout,
    do:
      :timer.seconds(5) +
        (__MODULE__ |> Application.get_application() |> Application.get_env(:timeout))
end
