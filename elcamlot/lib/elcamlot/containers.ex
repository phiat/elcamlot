defmodule Elcamlot.Containers do
  @moduledoc """
  Incus container lifecycle management — our "testcontainers" implementation.

  Provides programmatic control over Incus containers for development
  and integration testing. Spin up fresh Postgres instances, get their IPs,
  run health checks, and tear them down.
  """
  require Logger

  @default_image "images:ubuntu/noble"
  @pg_container "elcamlot-pg"
  @ocaml_container "elcamlot-ocaml"

  # --- Container Lifecycle ---

  @doc "Launch an Incus container. Returns {:ok, name} or {:error, reason}."
  def launch(name, opts \\ []) do
    image = Keyword.get(opts, :image, @default_image)

    case container_exists?(name) do
      true ->
        Logger.info("Container #{name} already exists, ensuring it's running")
        start(name)

      false ->
        case incus(["launch", image, name]) do
          {_, 0} ->
            Logger.info("Launched container #{name} from #{image}")
            wait_for_network(name)
            {:ok, name}

          {output, _} ->
            {:error, "Failed to launch #{name}: #{output}"}
        end
    end
  end

  @doc "Start a stopped container."
  def start(name) do
    case incus(["start", name]) do
      {_, 0} -> {:ok, name}
      {_, 1} -> {:ok, name}  # already running
      {output, _} -> {:error, output}
    end
  end

  @doc "Stop a running container."
  def stop(name) do
    case incus(["stop", name]) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  @doc "Delete a container (force stops if running)."
  def delete(name) do
    case incus(["delete", name, "--force"]) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  @doc "Stop and delete a container."
  def destroy(name) do
    delete(name)
  end

  # --- Container Info ---

  @doc "Get the IPv4 address of a container."
  def get_ip(name) do
    case incus(["list", name, "--format", "csv", "-c", "4"]) do
      {output, 0} ->
        ip =
          output
          |> String.trim()
          |> String.split(" ")
          |> List.first()

        if ip && ip != "", do: {:ok, ip}, else: {:error, :no_ip}

      {_, _} ->
        {:error, :not_found}
    end
  end

  @doc "Check if a container exists."
  def container_exists?(name) do
    case incus(["info", name]) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc "Get container state (RUNNING, STOPPED, etc)."
  def state(name) do
    case incus(["info", name]) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          case String.split(line, ":", parts: 2) do
            ["Status", value] -> String.trim(value)
            _ -> nil
          end
        end)

      _ ->
        nil
    end
  end

  @doc "List all Elcamlot containers."
  def list_containers do
    case incus(["list", "--format", "csv", "-c", "ns4"]) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "elcamlot-"))
        |> Enum.map(fn line ->
          [name, state, ipv4] = String.split(line, ",", parts: 3)
          %{name: name, state: state, ip: String.split(ipv4, " ") |> List.first()}
        end)

      {_, _code} ->
        []
    end
  end

  # --- Exec & Files ---

  @doc "Execute a command inside a container."
  def exec(name, command) when is_binary(command) do
    exec(name, ["--", "bash", "-c", command])
  end

  def exec(name, args) when is_list(args) do
    case incus(["exec", name | args]) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, code} -> {:error, {code, String.trim(output)}}
    end
  end

  @doc "Push a file into a container."
  def push_file(name, local_path, remote_path) do
    case incus(["file", "push", local_path, "#{name}#{remote_path}"]) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  # --- Postgres-specific helpers ---

  @doc "Launch a Postgres container with TimescaleDB using our infra scripts."
  def setup_postgres(opts \\ []) do
    name = Keyword.get(opts, :name, @pg_container)
    script_dir = Path.join([project_root(), "infra"])

    case System.cmd("bash", [Path.join(script_dir, "setup-pg.sh")],
           stderr_to_stdout: true,
           env: [{"CONTAINER_NAME", name}]
         ) do
      {output, 0} ->
        Logger.info("Postgres container ready: #{name}")

        case get_ip(name) do
          {:ok, ip} ->
            {:ok, %{name: name, ip: ip, port: 5432, output: output}}

          {:error, reason} ->
            {:error, "Container started but failed to get IP: #{inspect(reason)}"}
        end

      {output, code} ->
        {:error, "setup-pg.sh failed (exit #{code}): #{output}"}
    end
  end

  @doc "Check if Postgres is accepting connections."
  def pg_ready?(name \\ @pg_container) do
    case exec(name, "pg_isready -U elcamlot") do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc "Wait for Postgres to be ready, with timeout."
  def wait_for_pg(name \\ @pg_container, timeout_ms \\ 30_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_pg(name, deadline)
  end

  defp do_wait_pg(name, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      if pg_ready?(name) do
        :ok
      else
        Process.sleep(500)
        do_wait_pg(name, deadline)
      end
    end
  end

  # --- Teardown ---

  @doc "Tear down all Elcamlot containers."
  def teardown_all do
    [@pg_container, @ocaml_container]
    |> Enum.each(fn name ->
      if container_exists?(name) do
        Logger.info("Destroying container: #{name}")
        destroy(name)
      end
    end)

    :ok
  end

  # --- Private ---

  defp incus(args) do
    System.cmd("incus", args, stderr_to_stdout: true)
  end

  defp wait_for_network(name, retries \\ 30) do
    if retries <= 0 do
      Logger.warning("Timed out waiting for network on #{name}")
      :timeout
    else
      case get_ip(name) do
        {:ok, _ip} -> :ok
        _ ->
          Process.sleep(1000)
          wait_for_network(name, retries - 1)
      end
    end
  end

  defp project_root do
    # Navigate up from elcamlot/ to tc-lander/
    Application.app_dir(:elcamlot)
    |> Path.join("../../..")
    |> Path.expand()
  end
end
