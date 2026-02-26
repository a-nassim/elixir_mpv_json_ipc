defmodule MpvJsonIpc.Setup.Sup do
  @moduledoc false
  use Supervisor, restart: :transient

  @impl true
  def init(opts) do
    opts =
      opts
      |> Enum.into(%{
        ipc_server: "/tmp/mpv#{opts[:seed]}",
        start_mpv: true,
        log_level: nil,
        log_handler: nil,
        path: "mpv"
      })

    children = [
      {MpvJsonIpc.Task, opts},
      {MpvJsonIpc.Event, opts},
      {MpvJsonIpc.Setup, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  def name(seed), do: MpvJsonIpc.Connection.via(__MODULE__, seed)

  def start_link(opts \\ []) do
    seed = Enum.random(0..(2 ** 48))
    opts = opts |> Enum.into(%{seed: seed})

    Supervisor.start_link(__MODULE__, opts, name: name(seed))
  end

  @doc false
  def stop(server, reason \\ :normal)

  def stop(server, reason) when is_tuple(server) or is_pid(server),
    do: Supervisor.stop(server, reason)

  def stop(seed, reason), do: __MODULE__.name(seed) |> stop(reason)
end
