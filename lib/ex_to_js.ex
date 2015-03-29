defmodule ExToJS do

  defmodule Parser do
    defexception [:message]
  end

  @doc """
  Parses Elixir code string into JavaScript AST
  """
  @spec parse_elixir(binary) :: {binary, ESTree.Node.t}
  def parse_elixir(elixir_code) do
    elixir_code
    |> Code.string_to_quoted!
    |> parse_quoted
  end

  @doc """
  Parses Elixir code in it's quoted form into JavaScript AST
  """
  @spec parse_quoted(Macro.t) :: {binary, ESTree.Node.t}
  def parse_quoted(quoted) do
    js_ast = ExToJS.Translator.translate(quoted)
    {"output.json", js_ast}
  end

  @doc """
  Parses Elixir code files into JavaScript AST
  """
  @spec parse_elixir_files(binary) :: [{binary, ESTree.Node.t}]
  def parse_elixir_files(path) do
    path
    |> Path.wildcard
    |> Enum.map(fn(x) -> parse_elixir_file(x) end)     
  end

  defp parse_elixir_file(path) do
    js_ast = path
    |> File.read!
    |> Code.string_to_quoted!
    |> ExToJS.Translator.translate

    file_name = Path.basename(path, ".ex") <> ".json"

    {file_name, js_ast}
  end

  @doc """
  Converts JavaScript AST into JavaScript code
  """
  @spec javascript_ast_to_code([{binary, ESTree.Node.t}]) :: [{binary, binary} | {:error, binary}]
  def javascript_ast_to_code(js_ast) when is_list(js_ast) do
    Enum.map(js_ast, &javascript_ast_to_code(&1))
  end

  @doc """
  Converts JavaScript AST into JavaScript code
  """
  @spec javascript_ast_to_code({binary, ESTree.Node.t}) :: {binary, binary} | {:error, binary}
  def javascript_ast_to_code({ path, js_ast }) do
    case javascript_ast_to_code(js_ast) do
      {:ok, js_code} ->
        { Path.basename(path, ".json") <> ".js", js_code }
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Converts JavaScript AST into JavaScript code
  """
  @spec javascript_ast_to_code(ESTree.Node.t) :: {:ok, binary} | {:error, binary}
  def javascript_ast_to_code(js_ast) do
    path = try do
      Mix.Project.build_path <> "/lib/ex_to_js/priv/vendor"
    rescue
      UndefinedFunctionError ->
        "priv/vendor"
    end

    {_, alphonse } = Enum.map_reduce(["escodegen.browser.js", "alphonse.js"], "", fn(x, combined) ->
      {:ok, js } = File.read(path <> "/" <> x)
      { nil, combined <> "\n" <> js }
    end)

    {:ok, js} = :js_driver.new()

    :ok = :js.define(js, alphonse)
    {:ok, json} = Poison.encode(js_ast)


    {status, result} = :js.call(js, "createCode", [json])
    :js_driver.destroy(js)
    {status, result}
  end

  @doc """
  Writes output to file
  """
  @spec write_to_files([{binary, binary}], binary) :: nil
  def write_to_files(list, destination) when is_list(list) do
    Enum.each(list, &write_to_files(&1, destination))
  end

  @doc """
  Writes output to file
  """
  @spec write_to_files({binary, binary}, binary) :: :ok | no_return
  def write_to_files({file_name, js}, destination) do
    file_name = Path.join([destination, file_name])

    if !File.exists?(destination) do
      File.mkdir_p!(destination)
    end

    File.write!(file_name, js)
  end
end
