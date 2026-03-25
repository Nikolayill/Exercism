defmodule Dot do
  defmacro graph(do: block) do
    builder = get_node(block)

    quote do
      (fn ->
         graph = Graph.new()
         unquote(builder)
         graph
       end).()
    end
  end

  defp get_node(block) do
    case block do
      {:__block__, meta, [first_item | rest_items]} ->
        quote do
          unquote(get_node(first_item))
          unquote(get_node({:__block__, meta, rest_items}))
        end

      {:__block__, _meta, []} ->
        quote do
        end

      {:graph, _meta, [args]} ->
        quote do
          unquote(assert_kwlist(args))
          graph = Graph.put_attrs(graph, unquote(args))
        end

      {a, _meta, nil} when is_atom(a) ->
        quote do
          graph = Graph.add_node(graph, unquote(a))
        end

      {a, _meta, [args]} when is_atom(a) ->
        quote do
          unquote(assert_kwlist(args))
          graph = Graph.add_node(graph, unquote(a), unquote(args))
        end

      {:--, _meta, [{node1, _, nil}, {node2, _, nil}]} when is_atom(node1) and is_atom(node2) ->
        quote do
          graph = Graph.add_edge(graph, unquote(node1), unquote(node2))
        end

      {:--, _meta, [{node1, _, _}, {node2, _, [args]}]} when is_atom(node1) and is_atom(node2) ->
        quote do
          unquote(assert_kwlist(args))
          graph = Graph.add_edge(graph, unquote(node1), unquote(node2), unquote(args))
        end

      _ ->
        raise ArgumentError
    end
  end

  defp assert_kwlist(args) do
    if !Keyword.keyword?(args) do
      raise ArgumentError
    end

    args
  end
end
