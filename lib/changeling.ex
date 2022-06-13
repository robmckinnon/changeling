defmodule Changeling do
  @moduledoc """
  Elixir refactoring functions.
  """

  alias Sourceror.Zipper, as: Z

  defp d({{n, _, _}, _} = zipper, lab) do
    IO.inspect(n, label: lab)
    zipper
  end

  defp d(zipper, _), do: zipper

  defp remove_range({{:def, meta, [{marker, _, _}, _]}, _list} = zipper, from, to, acc) do
    acc =
      if meta[:line] < from do
        put_in(acc.def, marker)
      else
        acc
      end

    zipper |> Z.next() |> remove_range(from, to, acc)
  end

  defp remove_range({{marker, meta, _children}, _list} = zipper, from, to, acc) do
    if Z.end?(zipper) do
      d(zipper, "end")
      {zipper, put_in(acc.lines, Enum.reverse(acc.lines))}
    else
      if meta[:line] < from || meta[:line] > to || marker == :__block__ do
        # if Z.root(zipper) == Z.node(zipper) do
        zipper |> Z.next() |> remove_range(from, to, acc)
      else
        acc = put_in(acc.lines, [Z.node(zipper) | acc.lines])

        if is_nil(acc.replace_with) do
          zipper |> Z.remove() |> Z.next() |> remove_range(from, to, acc)
        else
          function_name = acc.replace_with
          acc = put_in(acc.replace_with, nil)

          zipper
          |> Z.replace({function_name, [], []})
          |> Z.next()
          |> remove_range(from, to, acc)
        end
      end
    end
  end

  defp remove_range(zipper, from, to, acc) do
    if Z.end?(zipper) do
      d(zipper, "end2")
      {zipper, put_in(acc.lines, Enum.reverse(acc.lines))}
    else
      d(zipper, "remove2")
      zipper |> Z.next() |> remove_range(from, to, acc)
    end
  end

  @doc """
  Return zipper containing AST for lines in the range from-to.
  """
  def extract_lines(zipper, from, to, replace_with \\ nil) do
    remove_range(zipper, from, to, %{lines: [], def: nil, replace_with: replace_with})
  end

  defp vars_declared(function_name, args, lines) do
    {_zipper, acc} =
      new_function(function_name, args, lines)
      |> Z.zip()
      |> vars_declared(%{vars: []})

    acc.vars
  end

  defp vars_declared({{:=, _, [{var, _, nil}, _]}, _rest} = zipper, acc) when is_atom(var) do
    vars_declared(zipper |> Z.next(), put_in(acc.vars, [var | acc.vars]))
  end

  defp vars_declared(zipper, acc) do
    if Z.end?(zipper) do
      {zipper, put_in(acc.vars, Enum.reverse(acc.vars))}
    else
      vars_declared(zipper |> Z.next(), acc)
    end
  end

  defp vars_used(function_name, args, lines) do
    {_zipper, acc} =
      new_function(function_name, args, lines)
      |> Z.zip()
      |> vars_used(%{vars: []})

    acc.vars
  end

  defp vars_used({{marker, _meta, nil}, _rest} = zipper, acc) when is_atom(marker) do
    vars_used(zipper |> Z.next(), put_in(acc.vars, [marker | acc.vars]))
  end

  defp vars_used(zipper, acc) do
    if Z.end?(zipper) do
      {zipper, put_in(acc.vars, Enum.reverse(acc.vars))}
    else
      vars_used(zipper |> Z.next(), acc)
    end
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

  def extract_function(zipper, from, to, function_name) do
    {{quoted, :end}, acc} = extract_lines(zipper, from, to, function_name)
    zipper = Z.zip(quoted)
    enclosing = acc.def

    args = []
    # [
    #   {:one, [trailing_comments: [], leading_comments: [], line: 2, column: 11],
    #    nil},
    #   {:two, [trailing_comments: [], leading_comments: [], line: 2, column: 16],
    #    nil}
    # ]
    declares = vars_declared(function_name, args, acc.lines)
    used = vars_used(function_name, args, acc.lines) -- declares
    args = Enum.map(used, fn var -> {var, [], nil} end)
    {zipper, extracted} = return_declared(zipper, declares, function_name, args, acc.lines)

    zipper
    |> top_find(fn
      {:def, _meta, [{^enclosing, _, _}, _]} -> true
      _ -> false
    end)
    |> Z.insert_right(extracted)
    |> fix_block()
    |> Z.root()
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
