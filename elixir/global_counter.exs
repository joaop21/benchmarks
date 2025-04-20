# This script benchmarks different concurrent counter implementations in Elixir
# comparing :counters, :atomics, and GenServer approaches

Mix.install([{:benchee, "~> 1.0"}])

defmodule ConcurrentCounterBenchmark do
  @moduledoc """
  Benchmarks different implementations of concurrent counters:
  - :counters with :atomics flag
  - :counters with :write_concurrency flag
  - :atomics (unsigned)
  - GenServer-based counter
  """

  @iterations 1_000
  @operations 10_000

  defmodule Counter do
    @moduledoc """
    A GenServer-based counter implementation
    """
    use GenServer

    def start_link(initial_value) do
      GenServer.start_link(__MODULE__, initial_value)
    end

    def init(initial_value), do: {:ok, initial_value}

    def handle_call(:get, _from, state), do: {:reply, state, state}

    def handle_call({:add, value}, _from, state) do
      new_state = state + value
      {:reply, new_state, new_state}
    end

    # Client API
    def add(pid, value), do: GenServer.call(pid, {:add, value})
    def get(pid), do: GenServer.call(pid, :get)
  end

  def setup_counters do
    counter_key = :counter

    ets_table =
      :ets.new(:counter_table, [
        :set,
        :public,
        :named_table,
        write_concurrency: true
        # read_concurrency: true
      ])

    :ets.insert(ets_table, {counter_key, 0})

    %{
      atomic_counter: :counters.new(1, [:atomics]),
      write_concurrency_counter: :counters.new(1, [:write_concurrency]),
      atomic_unsigned: :atomics.new(1, signed: false),
      genserver_counter: elem(Counter.start_link(1), 1),
      ets_counter: {ets_table, counter_key}
    }
  end

  def run_benchmark do
    counters = setup_counters()

    Benchee.run(%{
      ":counters with :atomics" => fn ->
        run_counter_benchmark(counters.atomic_counter, &counter_task/1)
      end,
      ":counters with :write_concurrency" => fn ->
        run_counter_benchmark(counters.write_concurrency_counter, &counter_task/1)
      end,
      ":atomics (unsigned)" => fn ->
        run_counter_benchmark(counters.atomic_unsigned, &atomic_task/1)
      end,
      "GenServer counter" => fn ->
        run_counter_benchmark(counters.genserver_counter, &genserver_task/1)
      end,
      "ETS counter" => fn ->
        run_counter_benchmark(counters.ets_counter, &ets_task/1)
      end
    })
  end

  # Private helper functions
  defp run_counter_benchmark(counter, task_fn) do
    1..@iterations
    |> Task.async_stream(fn _ -> task_fn.(counter) end)
    |> Stream.run()
  end

  defp counter_task(counter), do: run_task(counter, &:counters.add(&1, 1, &2))
  defp atomic_task(atomic), do: run_task(atomic, &:atomics.add(&1, 1, &2))
  defp genserver_task(pid), do: run_task(pid, &Counter.add/2)
  defp ets_task({table, key}), do: run_task({table, key}, &increment_ets/2)

  defp increment_ets({table, key}, increment) do
    :ets.update_counter(table, key, {2, increment})
  end

  defp run_task(counter, increment_fn) do
    Enum.reduce(1..@operations, :ok, fn _, _acc ->
      increment_fn.(counter, 1)
    end)
  end
end

# Run the benchmark
ConcurrentCounterBenchmark.run_benchmark()
