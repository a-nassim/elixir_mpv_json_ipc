defmodule MpvJsonIpc.Socket do
  @moduledoc false
  use GenServer
  require Logger

  @newlines ["\r\n", "\n", "\r"]

  @impl true
  def init(opts) do
    {:ok, opts[:seed], {:continue, {:wait, opts[:ipc_server]}}}
  end

  @impl true
  def handle_continue({:wait, ipc_server}, seed) do
    Process.sleep(:timer.seconds(1))

    {:ok, socket} = :gen_tcp.connect({:local, ipc_server}, 0, [:binary, active: :once])
    {:noreply, {socket, seed, ""}}
  end

  @impl true
  def handle_call({:send, data}, _from, {socket, seed, buffer}) do
    data
    |> encode()
    |> then(fn data -> :gen_tcp.send(socket, data <> "\n") end)

    {:reply, :ok, {socket, seed, buffer}}
  end

  @impl true
  def handle_info({:tcp, socket, data}, {socket, seed, buffer}) do
    :inet.setopts(socket, active: :once)
    buffer = buffer <> data

    if String.ends_with?(buffer, @newlines) do
      buffer
      |> String.splitter(@newlines)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&Jason.decode!(&1, keys: :atoms))
      |> Enum.each(&(MpvJsonIpc.Event.name(seed) |> MpvJsonIpc.Event.receive(&1)))

      {:noreply, {socket, seed, ""}}
    else
      {:noreply, {socket, seed, buffer}}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(_reason, {socket, _seed, _buffer}) do
    :gen_tcp.close(socket)
  end

  @doc false
  def name(seed), do: {:via, Registry, {Registry.MpvJsonIpc, "#{__MODULE__}#{seed}"}}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: name(opts[:seed]))

  def send(server, data) do
    GenServer.call(server, {:send, data})
  end

  defp encode(data) when is_map(data), do: data |> Jason.encode!()
  defp encode(data) when is_binary(data), do: data
end
