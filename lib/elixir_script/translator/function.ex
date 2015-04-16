defmodule ElixirScript.Translator.Function do
  require Logger
  alias ESTree.Builder
  alias ElixirScript.Translator

  def make_function_or_property_call(module_name, function_name) do
      Builder.call_expression(
        Builder.member_expression(
          Builder.identifier("ElixirScript"),
          Builder.identifier("get_property_or_call_function")
        ),        
        [
          Translator.translate(module_name),
          Builder.literal(to_string(function_name))
        ]
      )
  end

  def make_function_call(function_name, params) do
    Builder.call_expression(
      Builder.identifier(function_name),
      Enum.map(params, &Translator.translate(&1))
    )
  end

  def make_function_call(module_name, function_name, params) do
    the_name = case module_name do
      {:__aliases__, _, name} ->
        name
      {name, _, _} ->
        name
      name ->
        case to_string(name) do
          "Elixir." <> actual_name ->
            actual_name
          _ ->
            name
        end
    end


    Builder.call_expression(
      Builder.member_expression(
        Builder.identifier(the_name),
        Builder.identifier(function_name)
      ),
      Enum.map(params, &Translator.translate(&1))
    )
  end

  def make_function(name, params, body, guards \\ nil) do
    do_make_function(name, params, body, guards)
  end

  def make_export_function(name, params, body, guards \\ nil) do
    do_make_function(name, params, body, guards)
    |> Builder.export_declaration
  end

  defp handle_guards(guards) do
    Enum.map(guards, &Translator.translate(&1))
  end

  defp do_make_function(name, params, body, guards \\ nil) do
    body = prepare_function_body(body)

    body = if guards do
      [Builder.if_statement(
        hd(handle_guards(guards)),
        Builder.block_statement(body),
        Builder.block_statement([
          Builder.throw_statement(
            Builder.new_expression(
              Builder.identifier("FunctionClauseError"),
              [
                Builder.literal("no function clause matching in #{name}/#{length(params)}")
              ]
            )
          )
        ])
      )]
    else
      body
    end

    Builder.function_declaration(
      Builder.identifier(name),
      Enum.map(params, &Translator.translate(&1)),
      [],
      Builder.block_statement(body)
    )
  end

  def make_anonymous_function(params, body) do
    Builder.function_expression(
      Enum.map(params, &Translator.translate(&1)),
      [],
      Builder.block_statement(prepare_function_body(body))
    )
  end

  defp prepare_function_body(body) do
    body = cond do
      body == nil ->
        []
      is_list(body) ->
        Enum.map(body, &Translator.translate(&1))
      true ->
        [Translator.translate(body)]
    end

    return_last_expression(body)
  end

  def return_last_expression([]) do
    [Builder.return_statement(Builder.literal(nil))]
  end

  def return_last_expression(%ESTree.BlockStatement{} = block) do
    %ESTree.BlockStatement{ block | body: return_last_expression(block.body) }
  end

  def return_last_expression(list) when is_list(list) do
    last_item = List.last(list)

    last_item = case last_item do
      %ESTree.Literal{} ->
        Builder.return_statement(last_item) 
      %ESTree.Identifier{} ->
        Builder.return_statement(last_item) 
      %ESTree.VariableDeclaration{} ->
        declaration = hd(last_item.declarations).id

        return_statement = case declaration do
          %ESTree.ArrayPattern{} ->
            Builder.return_statement(Builder.array_expression(declaration.elements))
          _ ->
            Builder.return_statement(declaration)  
        end

        [last_item, return_statement]
      %ESTree.BlockStatement{} ->
        last_item = %ESTree.BlockStatement{ last_item | body: return_last_expression(last_item.body) }
      _ ->
        if String.contains?(last_item.type, "Expression") do
          Builder.return_statement(last_item) 
        else
          [last_item, Builder.return_statement(Builder.literal(nil))]
        end    
    end


    list = Enum.take(list, length(list)-1) 
    |> Enum.map(fn(x) ->
      case x do
        %ESTree.MemberExpression{} ->
          Builder.expression_statement(x)
        %ESTree.CallExpression{} ->
          Builder.expression_statement(x)
        _ ->
          x
      end
    end)

    if is_list(last_item) do
      list ++ last_item
    else
      list ++ [last_item]
    end
  end

end