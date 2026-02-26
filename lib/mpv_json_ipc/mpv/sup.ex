defmodule MpvJsonIpc.Mpv.Sup do
  @moduledoc """
  A Supervisor for an MPV instance.
  """
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
      {MpvJsonIpc.Mpv, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  def name(seed), do: MpvJsonIpc.Connection.via(__MODULE__, seed)

  @doc """
  Returns the the server instance that you can interract with using `Mpv`

  ## Examples
      {:ok, sup} = MpvJsonIpc.Mpv.Sup.start_link()
      main = MpvJsonIpc.Mpv.Sup.main(sup)
      # When you don't know the supervisor pid (e.g. MpvJsonIpc.Mpv.Sup directly started in the supervision tree)
      {_, sup} = MpvJsonIpc.running_sups() |> List.first()
      main = MpvJsonIpc.Mpv.Sup.main(sup)
      MpvJsonIpc.Mpv.command(main, "get_property", "playback-time")
  """
  def main(pid),
    do: pid |> Supervisor.which_children() |> List.keyfind!(MpvJsonIpc.Mpv, 0) |> elem(1)

  @doc """
  Starts the the supervisor.

  The following options can be set:

  * `:start_mpv` - Whether to start an MPV instance; default: `true`.
  If this is set to `false`, `:ipc_server` must also be set.
  * `:ipc_server` - the path of the IPC server, of the already running MPV instance.
  * `:path` - the path of the MPV executable.
  If this is not set, it looks for MPV in the `$PATH`.
  * `:log_level` - Whether to receive log messages from the MPV instance.
  If this is set, `:log_handler` must also be set.
  Available levels are described [here](https://mpv.io/manual/master/#options-msg-level)
  * `:log_handler` - a function that process log messages.

  ## Examples
      # Uses the MPV executable found in the `$PATH`
      MpvJsonIpc.Mpv.Sup.start_link()
      # Uses a running MPV connected to /tmp/mpvsocket
      MpvJsonIpc.Mpv.Sup.start_link(start_mpv: false, ipc_server: "/tmp/mpvsocket")
      # Uses the MPV executable found at /path/to/mpv
      MpvJsonIpc.Mpv.Sup.start_link(path: "/path/to/mpv")
      # Calls `IO.inspect/1` on all messages with level `:debug` or above
      MpvJsonIpc.Mpv.Sup.start_link(log_level: :debug, log_handler: &IO.inspect/1)
  """
  def start_link(opts \\ []) do
    seed = Enum.random(0..(2 ** 48))
    opts = opts |> Enum.into(%{seed: seed})

    Supervisor.start_link(__MODULE__, opts, name: name(seed))
  end

  @doc """
  Stops the supervisor.
  """
  def stop(server, reason \\ :normal)

  def stop(server, reason) when is_tuple(server) or is_pid(server),
    do: Supervisor.stop(server, reason)

  def stop(seed, reason), do: __MODULE__.name(seed) |> stop(reason)
end
