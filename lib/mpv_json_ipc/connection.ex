defmodule MpvJsonIpc.Connection do
  @moduledoc false
  require Logger

  def via(module, seed), do: {:via, Registry, {Registry.MpvJsonIpc, "#{module}#{seed}"}}

  def connect(opts) do
    Logger.debug("Mpv basic init", seed: opts[:seed])

    if opts[:start_mpv] do
      Port.open(
        {:spawn_executable, wrapper_path()},
        [
          :binary,
          :exit_status,
          args: [
            opts[:path],
            "--idle",
            "--input-ipc-server=#{opts[:ipc_server]}",
            "--no-input-terminal",
            "--no-terminal"
          ]
        ]
      )
    end

    request_id = observer_id = keybind_id = 1
    {:ok, _} = MpvJsonIpc.Socket.start_link(opts)
    {%{request_id: request_id, observer_id: observer_id, keybind_id: keybind_id}, opts}
  end

  def log_setup({log_level, log_handler}, {state, seed}) do
    Logger.debug("Mpv logs setup", seed: seed)

    if log_level && log_handler && is_function(log_handler, 1) do
      :ok =
        MpvJsonIpc.Event.name(seed)
        |> MpvJsonIpc.Event.add_event_callback("log-message", log_handler)

      cmd = %{command: [:request_log_messages, log_level]}
      {:ok, new_state} = command(cmd, state, seed)
      new_state
    else
      state
    end
  end

  def command(cmd, state, seed) do
    ref = make_ref()

    {cmd, new_state} = add_request_id({cmd, state}, seed, {ref, self()})

    :ok = MpvJsonIpc.Socket.name(seed) |> MpvJsonIpc.Socket.send(cmd)

    reply =
      receive do
        {^ref, reply} ->
          reply
      after
        timeout() ->
          {:error, :timeout}
      end

    {reply, new_state}
  end

  def timeout,
    do:
      :timer.seconds(5) +
        (MpvJsonIpc.Connection |> Application.get_application() |> Application.get_env(:timeout))

  def wrapper_path,
    do:
      System.tmp_dir!()
      |> Path.join(MpvJsonIpc.Connection |> Application.get_application() |> to_string)
      |> Path.join("wrapper.sh")

  defp add_request_id({cmd, state}, seed, from) when is_map(cmd) do
    :ok = MpvJsonIpc.Event.name(seed) |> MpvJsonIpc.Event.reply(state[:request_id], from)
    cmd = cmd |> Map.put(:request_id, state[:request_id])
    new_state = state |> Map.update!(:request_id, &(&1 + 1))
    {cmd, new_state}
  end

  defp add_request_id({cmd, _state} = arg, _seed, _from)
       when is_binary(cmd),
       do: arg
end
