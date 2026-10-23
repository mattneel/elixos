defmodule ElixosDemo do
  @moduledoc """
  A supervised measurement journal with durable local state and shared statistics.

  Record numeric observations by label, retrieve them in chronological order,
  and summarize a label (or all observations) using the separate ordinary
  `elixos_demo_stats` package:

      ElixosDemo.record("room_celsius", 21.5)
      ElixosDemo.record("room_celsius", 22)
      ElixosDemo.summary("room_celsius")
      # %{count: 2, min: 21.5, max: 22, mean: 21.75}
      ElixosDemo.readings()

  A successful write is synced to a temporary file and renamed before the
  caller receives its reading. Service restarts and code replacement reload
  the file. The target state is `/priv/data/elixos_demo/state/readings.etf`,
  outside installed ebin/priv. This is ordinary filesystem durability; Live
  RAM is lost on a kernel reboot, and no snapshots/mounts are created here.

  ## Host development and source packaging

  In this source checkout, run
  `MIX_ENV=test mix deps.get --only test --target host` then `mix test`. This
  uses the sibling `elixos_demo_stats` project as a normal path dependency.
  Production and target builds always declare its ordinary `~> 0.1` Hex
  requirement. The only OS dependency is
  `{:elixos, "~> 0.1", targets: :elixos}`. Host compilation neither loads the
  OS-only source directory nor starts Elixos. Always select `--target host`
  when fetching host dependencies: plain Mix fetches across all targets.

  With the SDK archive and Hex installed, package production target source on
  the host with `MIX_ENV=prod MIX_TARGET=elixos mix elixos.package`. The existing
  repository workflow packages all official source projects with
  `hex/build-packages.sh`, using the same SDK-aware dependency filter rather
  than plain `mix hex.build`, which does not filter dependencies by target.
  Packages include target config/source but no compiled artifacts or dependency
  code. Do not compile the Elixos target or fetch the OS on the host.

  Publish tarballs with existing Hex tools. A repository URL is not trust:
  explicitly provide its verified RSA public key to `mix hex.repo add` on a
  host or `Elixos.Package.add_repo(:repo, url, key: public_key_pem)` in Elixos.
  Neither the demo nor SDK reads signing keys or adds trusted repositories.

  ## Native Elixos use

  In real Elixos, after that explicit trust step:

      Elixos.Package.install(:elixos_demo)
      ElixosDemo.record("room_celsius", 21.5)
      ElixosDemo.os_info()
      # {:ok, %{boot: Elixos.info(), data_dir: "/priv/data/elixos_demo"}}

  Installation builds natively against the running OS and the single installed
  shared dependency, then supervises `ElixosDemo.Supervisor`. `boot: :auto`
  restores this service after a saved generation boots on durable storage.
  The target-only `ElixosDemo.OS` module calls real public OS APIs. On a host,
  `os_info/0` returns `{:error, :elixos_target_required}`, not fabricated facts.
  """

  @doc "Records a labelled number; invalid readings and failed writes return errors."
  def record(label, value), do: ElixosDemo.Journal.record(ElixosDemo.Journal, label, value)

  @doc "Returns persisted readings in insertion order."
  def readings, do: ElixosDemo.Journal.readings(ElixosDemo.Journal)

  @doc "Summarizes one label, or all readings with the default :all."
  def summary(label \\ :all), do: ElixosDemo.Journal.summary(ElixosDemo.Journal, label)

  @doc "Returns genuine native boot/data-directory observations, or an explicit host error."
  def os_info do
    case Application.fetch_env!(:elixos_demo, :os_observer) do
      nil -> {:error, :elixos_target_required}
      observer -> {:ok, observer.info()}
    end
  end
end
