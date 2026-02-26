defmodule MpvJsonIpc.Socket do
  @moduledoc false
  use GenServer
  require Logger

  @newlines ["\r\n", "\n", "\r"]

  @impl true
  def init(opts) do
    opts =
      opts
      |> Enum.into(%{ipc_server: "/tmp/mpvsocket"})

    {:ok, opts[:seed], {:continue, {:wait, opts[:ipc_server]}}}
  end

  @impl true
  def handle_continue({:wait, ipc_server}, seed) do
    Process.sleep(:timer.seconds(1))

    {:ok, socket} = :socket.open(:local, :stream)
    :ok = :socket.connect(socket, %{family: :local, path: ipc_server})

    receiver = Task.async(__MODULE__, :receive_loop, [socket, seed])
    {:noreply, {socket, receiver}}
  end

  @impl true
  def handle_call({:send, data}, _from, {socket, receiver}) do
    data
    |> encode()
    |> then(fn data -> :socket.send(socket, data <> "\n") end)

    {:reply, :ok, {socket, receiver}}
  end

  @impl true
  def terminate(:normal, {socket, receiver}) do
    Task.shutdown(receiver)
    :socket.close(socket)
  end

  @doc false
  def name(seed), do: {:via, Registry, {Registry.MpvJsonIpc, "#{__MODULE__}#{seed}"}}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: name(opts[:seed]))

  def send(server, data) do
    GenServer.call(server, {:send, data})
  end

  def receive_loop(socket, seed, start \\ "") do
    {:ok, data} = :socket.recv(socket, 0)

    if String.ends_with?(data, @newlines) do
      (start <> data)
      |> String.splitter(@newlines)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&Jason.decode!(&1, keys: :atoms))
      |> Enum.each(&(MpvJsonIpc.Event.name(seed) |> MpvJsonIpc.Event.receive(&1)))

      receive_loop(socket, seed)
    else
      receive_loop(socket, seed, start <> data)
    end
  end

  defp encode(data) when is_map(data), do: data |> Jason.encode!()
  defp encode(data) when is_binary(data), do: data
end
