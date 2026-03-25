defmodule React do
  defmodule InputHandle do
    @moduledoc false
    @type t :: %InputHandle{
            data: CellData.t()
          }

    @enforce_keys [:data]
    defstruct [
      :data
    ]
  end

  defmodule InputMappings do
    @moduledoc false
    @type t :: %InputMappings{
            cell_names: [String.t()],
            fx: fun()
          }

    @enforce_keys [:cell_names, :fx]
    defstruct [
      :cell_names,
      :fx
    ]
  end

  defmodule OutputHandle do
    @moduledoc false
    @type t :: %OutputHandle{
            data: CellData.t() | nil,
            inputs: InputMappings.t()
          }

    @enforce_keys [:inputs]
    defstruct [
      :data,
      :inputs
    ]
  end

  defmodule CellData do
    @moduledoc false
    @type t :: %CellData{
            value: any,
            event_id: non_neg_integer()
          }

    @enforce_keys [:value, :event_id]
    defstruct [
      :value,
      :event_id
    ]
  end

  @opaque cells :: pid

  @type cell :: {:input, String.t(), any} | {:output, String.t(), [String.t()], fun()}

  @doc """
  Start a reactive system
  """
  @spec new(cells :: [cell]) :: {:ok, pid}
  def new(cells) do
    {_inputs, outputs} =
      cells
      |> Enum.split_with(&(elem(&1, 0) == :input))

    subscriptions =
      outputs
      |> Enum.flat_map(fn {:output, subscriber, keys, _} ->
        Enum.map(keys, fn key -> {key, subscriber} end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    values =
      cells
      |> Enum.map(fn
        {:input, name, value} -> map_input(name, value)
        {:output, name, inputs, mapper_fun} -> map_output(name, inputs, mapper_fun)
      end)
      |> Map.new()

    initial_queue =
      subscriptions
      |> Map.values()
      |> Enum.flat_map(& &1)
      |> Enum.sort()
      |> Enum.dedup()

    result =
      update_values(subscriptions, values, 1, initial_queue)

    Agent.start_link(fn -> {result, %{}} end)
  end

  defp update_values(subscriptions, values, event_id, nil), do: {subscriptions, values, event_id}
  defp update_values(subscriptions, values, event_id, []), do: {subscriptions, values, event_id}

  defp update_values(subscriptions, values, event_id, [sub | queue]) do
    %React.OutputHandle{
      data: _data,
      inputs: %React.InputMappings{
        cell_names: inputs,
        fx: mapper
      }
    } = Map.get(values, sub)

    params =
      inputs
      |> Enum.map(&Map.get(values, &1))

    if not params_evaluated?(params, event_id) do
      # some params are not evaluated, move sub to the end of queue
      update_values(subscriptions, values, event_id, Enum.concat(queue, [sub]))
    else
      out_value =
        Enum.map(params, fn
          %React.OutputHandle{data: %CellData{value: value}} -> value
          %React.InputHandle{data: %CellData{value: value}} -> value
        end)
        |> call_dynamic(mapper)

      # updated values
      updated_values =
        values
        |> Map.update!(sub, fn v = %React.OutputHandle{} ->
          case v do
            %React.OutputHandle{data: %CellData{value: ^out_value}} -> v
            _ -> %React.OutputHandle{v | data: %CellData{value: out_value, event_id: event_id}}
          end
        end)

      chained = Map.get(subscriptions, sub, [])
      update_values(subscriptions, updated_values, event_id, Enum.concat(queue, chained))
    end
  end

  defp params_evaluated?(params, event_id) do
    Enum.all?(params, fn
      %React.OutputHandle{data: %CellData{value: _v, event_id: eid}} when eid == event_id -> true
      %React.OutputHandle{data: %CellData{value: _v, event_id: eid}} when eid != event_id -> false
      %React.OutputHandle{data: nil} -> false
      %React.InputHandle{data: _} -> true
    end)
  end

  defp map_input(name, value) do
    {name, %InputHandle{data: %CellData{value: value, event_id: 0}}}
  end

  defp map_output(name, inputs, mapper_fun) do
    {name, %OutputHandle{inputs: %InputMappings{cell_names: inputs, fx: mapper_fun}}}
  end

  defp call_dynamic(params, callee) do
    apply(callee, params)
  end

  @doc """
  Return the value of an input or output cell
  """
  @spec get_value(cells :: pid, cell_name :: String.t()) :: any()
  def get_value(cells, cell_name) do
    {state, _} = Agent.get(cells, & &1)

    value = Map.get(elem(state, 1), cell_name)

    %React.CellData{value: result} = Map.get(value, :data)
    result
  end

  @doc """
  Set the value of an input cell
  """
  @spec set_value(cells :: pid, cell_name :: String.t(), value :: any) :: :ok
  def set_value(cells, cell_name, value) do
    Agent.update(cells, fn {{subscriptions, values, event_id}, callbacks} ->
      next_event_id = event_id + 1

      updated_values =
        values
        |> Map.update!(cell_name, fn %React.InputHandle{} = input_handle ->
          %React.InputHandle{
            input_handle
            | data: %React.CellData{value: value, event_id: event_id}
          }
        end)

      updated_queue = Map.get(subscriptions, cell_name)

      result_state = update_values(subscriptions, updated_values, next_event_id, updated_queue)
      trigger_callbacks(result_state, callbacks, event_id)
      {result_state, callbacks}
    end)
  end

  @doc """
  Add a callback to an output cell
  """
  @spec add_callback(
          cells :: pid,
          cell_name :: String.t(),
          callback_name :: String.t(),
          callback :: fun()
        ) :: :ok
  def add_callback(cells, cell_name, callback_name, callback) do
    Agent.update(cells, fn {state, callbacks} ->
      {
        state,
        Map.update(
          callbacks,
          cell_name,
          %{callback_name => callback},
          fn callback_map -> Map.put(callback_map, callback_name, callback) end
        )
      }
    end)
  end

  @doc """
  Remove a callback from an output cell
  """
  @spec remove_callback(cells :: pid, cell_name :: String.t(), callback_name :: String.t()) :: :ok
  def remove_callback(cells, cell_name, callback_name) do
    Agent.update(cells, fn {state, callbacks} ->
      {
        state,
        Map.update(
          callbacks,
          cell_name,
          %{},
          &Map.delete(&1, callback_name)
        )
      }
    end)
  end

  defp trigger_callbacks({_subscriptions, values, _event_id}, callbacks, current_event_id) do
    callback_cells =
      callbacks
      |> Map.keys()

    values
    |> Map.to_list()
    |> Enum.filter(&Enum.member?(callback_cells, elem(&1, 0)))
    |> Enum.filter(fn
      {_, %React.OutputHandle{data: %React.CellData{event_id: cell_event_id}}}
      when cell_event_id > current_event_id ->
        true

      _ ->
        false
    end)
    |> run_callbacks(callbacks)
  end

  defp run_callbacks(updated_values, callbacks) do
    updated_values
    |> Enum.each(fn
      {cell_name, %React.OutputHandle{data: %React.CellData{value: value}}} ->
        Map.get(callbacks, cell_name)
        |> Map.to_list()
        |> Enum.each(fn {callback_name, callback_fun} ->
          apply(callback_fun, [callback_name, value])
        end)

      _ ->
        nil
    end)
  end
end
