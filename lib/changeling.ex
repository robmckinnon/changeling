defmodule Changeling do
  @moduledoc """
  Elixir refactoring functions.
  """

  alias Sourceror.Zipper, as: Z

  def extract_function(zipper, from, to, function_name) do
    {quoted, acc} = extract_lines(zipper, from, to, function_name)
    zipper = Z.zip(quoted)

    declares = vars_declared(function_name, [], acc.lines) |> Enum.uniq()
    used = vars_used(function_name, [], acc.lines) |> Enum.uniq()
    args = Enum.map(used -- declares, fn var -> {var, [], nil} end)
    returns = declares |> Enum.filter(&(&1 in acc.vars))
    {zipper, extracted} = return_declared(zipper, returns, function_name, args, acc.lines)

    enclosing = acc.def

    zipper
    |> top_find(fn
      {:def, _meta, [{^enclosing, _, _}, _]} -> true
      _ -> false
    end)
    |> Z.insert_right(extracted)
    |> fix_block()
    |> Z.root()
  end

  @doc """
  Return zipper containing AST for lines in the range from-to.
  """
  def extract_lines(zipper, from, to, replace_with \\ nil) do
    remove_range(zipper, from, to, %{
      lines: [],
      def: nil,
      def_end: nil,
      vars: [],
      replace_with: replace_with
    })
  end

  defp next_remove_range(zipper, from, to, acc) do
    if next = Z.next(zipper) do
      remove_range(next, from, to, acc)
    else
      # return zipper with lines removed
      {
        elem(Z.top(zipper), 0),
        %{acc | lines: Enum.reverse(acc.lines), vars: Enum.reverse(acc.vars)}
      }
    end
  end

  defp remove_range({{:def, meta, [{marker, _, _}, _]}, _list} = zipper, from, to, acc) do
    acc =
      if meta[:line] < from do
        x = put_in(acc.def, marker)
        put_in(x.def_end, meta[:end][:line])
      else
        acc
      end

    next_remove_range(zipper, from, to, acc)
  end

  defp remove_range({{marker, meta, children}, _list} = zipper, from, to, acc) do
    if meta[:line] < from || meta[:line] > to || marker == :__block__ do
      next_remove_range(
        zipper,
        from,
        to,
        if meta[:line] > to && meta[:line] < acc.def_end && is_atom(marker) && is_nil(children) do
          put_in(acc.vars, [marker | acc.vars] |> Enum.uniq())
        else
          acc
        end
      )
    else
      acc = put_in(acc.lines, [Z.node(zipper) | acc.lines])

      if is_nil(acc.replace_with) do
        zipper
        |> Z.remove()
        |> next_remove_range(from, to, acc)
      else
        function_name = acc.replace_with
        acc = put_in(acc.replace_with, nil)

        zipper
        |> Z.replace({function_name, [], []})
        |> next_remove_range(from, to, acc)
      end
    end
  end

  defp remove_range(zipper, from, to, acc) do
    next_remove_range(zipper, from, to, acc)
  end

  defp vars_declared(function_name, args, lines) do
    function_name
    |> new_function(args, lines)
    |> Z.zip()
    |> vars_declared(%{vars: []})
  end

  defp vars_declared(nil, acc) do
    Enum.reverse(acc.vars)
  end

  defp vars_declared({{:=, _, [{var, _, nil}, _]}, _rest} = zipper, acc) when is_atom(var) do
    zipper
    |> Z.next()
    |> vars_declared(put_in(acc.vars, [var | acc.vars]))
  end

  defp vars_declared(zipper, acc) do
    zipper
    |> Z.next()
    |> vars_declared(acc)
  end

  defp vars_used(function_name, args, lines) do
    function_name
    |> new_function(args, lines)
    |> Z.zip()
    |> vars_used(%{vars: []})
  end

  defp vars_used(nil, acc) do
    Enum.reverse(acc.vars)
  end

  defp vars_used({{marker, _meta, nil}, _rest} = zipper, acc) when is_atom(marker) do
    zipper
    |> Z.next()
    |> vars_used(put_in(acc.vars, [marker | acc.vars]))
  end

  defp vars_used(zipper, acc) do
    zipper
    |> Z.next()
    |> vars_used(acc)
  end

  defp return_declared(zipper, nil = _declares, function_name, args, lines) do
    {zipper, new_function(function_name, args, lines)}
  end

  defp return_declared(zipper, [var], function_name, args, lines) when is_atom(var) do
    zipper =
      zipper
      |> top_find(fn
        {^function_name, [], []} -> true
        _ -> false
      end)
      |> Z.replace({:=, [], [{var, [], nil}, {function_name, [], args}]})

    {zipper, new_function(function_name, args, Enum.concat(lines, [{var, [], nil}]))}
  end

  defp return_declared(zipper, declares, function_name, args, lines) when is_list(declares) do
    declares = Enum.reduce(declares, {}, fn var, acc -> Tuple.append(acc, {var, [], nil}) end)

    zipper =
      zipper
      |> top_find(fn
        {^function_name, [], []} -> true
        _ -> false
      end)
      |> Z.replace(
        {:=, [],
         [
           {:__block__, [],
            [
              declares
            ]},
           {function_name, [], args}
         ]}
      )

    {zipper,
     new_function(
       function_name,
       args,
       Enum.concat(lines, [
         {:__block__, [],
          [
            declares
          ]}
       ])
     )}
  end

  defp new_function(function_name, args, lines) do
    {:def, [do: [], end: []],
     [
       {function_name, [], args},
       [
         {
           {:__block__, [], [:do]},
           {:__block__, [], lines}
         }
       ]
     ]}
  end

  defp fix_block(zipper) do
    zipper
    |> top_find(fn
      {:{}, [], _children} -> true
      _ -> false
    end)
    |> case do
      nil ->
        zipper

      {{:{}, [], [block | defs]}, meta} ->
        {
          {
            block,
            {:__block__, [], defs}
          },
          meta
        }
    end
  end

  defp top_find(zipper, function) do
    zipper
    |> Z.top()
    |> Z.find(function)
  end
end
