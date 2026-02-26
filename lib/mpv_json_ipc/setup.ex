defmodule MpvJsonIpc.Setup do
  @moduledoc false
  use GenServer, restart: :transient
  require Logger

  alias MpvJsonIpc.Connection

  @doc false
  def name(seed), do: Connection.via(__MODULE__, seed)

  @doc false
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: name(opts[:seed]))

  @impl true
  def init(opts) do
    :ok = File.mkdir_p!(Path.dirname(Connection.wrapper_path()))
    :ok = File.write!(Connection.wrapper_path(), wrapper())
    :ok = File.chmod!(Connection.wrapper_path(), 0o700)

    {%{request_id: request_id, observer_id: observer_id, keybind_id: keybind_id}, opts} =
      Connection.connect(opts)

    {:ok,
     {%{request_id: request_id, observer_id: observer_id, keybind_id: keybind_id}, opts[:seed]},
     {:continue, {:logs, opts[:log_level], opts[:log_handler]}}}
  end

  @impl true
  def handle_continue({:logs, log_level, log_handler}, {state, seed}) do
    new_state = Connection.log_setup({log_level, log_handler}, {state, seed})
    {:noreply, {new_state, seed}, {:continue, :commands}}
  end

  @impl true
  def handle_call({:command, cmd}, _from, {state, seed}) do
    {reply, new_state} = Connection.command(cmd, state, seed)
    {:reply, reply, {new_state, seed}}
  end

  @impl true
  def handle_continue(:commands, {state, seed}) do
    Logger.debug("Mpv commands setup", seed: seed)
    cmd = %{command: [:get_property, :"command-list"]}
    {{:ok, command_list}, new_state} = Connection.command(cmd, state, seed)

    contents =
      command_list
      |> Stream.map(& &1[:name])
      |> Stream.map(&String.replace(&1, "-", "_"))
      |> Stream.map(&String.to_atom/1)
      |> Enum.map(fn name ->
        quote do
          def unquote(name)(server, args \\ [])

          def unquote(name)(server, arg) when is_binary(arg) or is_atom(arg) do
            MpvJsonIpc.Mpv.command(server, unquote(name), arg)
          end

          def unquote(name)(server, args) do
            MpvJsonIpc.Mpv.command(server, unquote(name), args)
          end
        end
      end)

    Module.create(MpvJsonIpc.Mpv.Commands, contents, Macro.Env.location(__ENV__))

    {:noreply, {new_state, seed}, {:continue, :properties}}
  end

  @impl true
  def handle_continue(:properties, {state, seed}) do
    Logger.debug("Mpv properties setup", seed: seed)
    cmd = %{command: [:get_property, :"property-list"]}
    {{:ok, property_list}, new_state} = Connection.command(cmd, state, seed)

    property_list
    |> Enum.each(fn name ->
      module_name = name |> String.capitalize() |> String.replace("-", "_")
      name = String.to_atom(name)

      contents = [
        quote do
          def get(server) do
            MpvJsonIpc.Mpv.command(server, :get_property, [unquote(name)])
          end
        end,
        quote do
          def set(server, value) do
            MpvJsonIpc.Mpv.command(server, :set_property, [unquote(name), value])
          end
        end
      ]

      MpvJsonIpc.Mpv.Properties
      |> Module.concat(module_name)
      |> Module.create(contents, Macro.Env.location(__ENV__))
    end)

    Logger.debug("Mpv fully setup", seed: seed)
    {:noreply, {new_state, seed}, {:continue, :stop}}
  end

  @impl true
  def handle_continue(:stop, {state, seed}) do
    :ok = MpvJsonIpc.__loaded__()
    Task.start(fn -> :ok = MpvJsonIpc.Setup.Sup.stop(seed) end)
    {:noreply, {state, seed}}
  end

  defp wrapper(), do: unquote(File.read!("priv/wrapper.sh"))
end
