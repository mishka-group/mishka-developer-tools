defmodule MishkaDeveloperTools.Helper.Derive.Parser do
  def parser(inputs) when is_list(inputs) do
    Enum.map(inputs, &parser(&1))
  end

  def parser(input) do
    String.split(String.trim(input), ")")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn x ->
      case Code.string_to_quoted!(String.trim(x) <> ")") do
        {key, _, parameters} ->
          convert_parameters(key, parameters)

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil(&1))
    |> merge_parser_list()
  rescue
    # We do not check the drive in compile time, so we need to pass nil
    _e -> nil
  end

  def convert_to_atom_map({:error, _, _, _} = error), do: error

  def convert_to_atom_map({:ok, map}) when is_map(map), do: convert_to_atom_map(map)

  def convert_to_atom_map(map) when is_map(map) do
    for {key, value} <- map, into: %{}, do: {convert_key(key), convert_value(value)}
  end

  defp convert_key(key) when is_binary(key), do: String.to_atom(key)

  defp convert_key(key), do: key

  defp convert_value(%{} = map), do: convert_to_atom_map(map)

  defp convert_value([]), do: []

  defp convert_value(list) when is_list(list), do: Enum.map(list, &convert_value/1)

  defp convert_value(value), do: value

  def convert_parameters(derive_key, parameters) do
    converted =
      parameters
      |> Enum.map(fn
        {key, _, nil} ->
          key

        {:=, _, [{key, _, nil}, {value, _, nil}]} when is_atom(value) ->
          {key, Atom.to_string(value)}

        {:=, _, [{key, _, nil}, value]} when is_integer(value) ->
          {key, value}

        {:=, _, [{key, _, nil}, value]} when is_list(value) and key == :custom ->
          case value do
            [{:__aliases__, _, module_list}, {function, _, nil}] ->
              {key, {module_list, function}}

            _ ->
              nil
          end

        {:=, _, [{key, _, nil}, value]} when is_list(value) ->
          if Enum.any?(value, &is_tuple(&1)),
            do: convert_parameters(key, value),
            else: {key, value}

        {:=, _, [{key, _, nil}, {_, _, [{:__aliases__, _, [type]} | _t]} = value]}
        when is_tuple(value) and is_atom(type) ->
          {key, Macro.to_string(value)}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil(&1))

    if converted == [], do: nil, else: Map.put(%{}, derive_key, converted)
  end

  defp merge_parser_list([]), do: nil

  defp merge_parser_list(list_of_maps) do
    Enum.reduce(list_of_maps, %{}, fn map, acc ->
      Map.merge(acc, map)
    end)
  end

  def parse_core_keys_pattern(pattern) do
    pattern
    |> String.trim()
    |> String.split("::", trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  @doc false
  def is_data?(%{data: [], errors: []}), do: true

  def is_data?(%{data: [], errors: errors}) when errors != [], do: false

  def is_data?(%{data: data, errors: errors}) when data != [] and errors == [], do: true

  def is_data?(%{data: _data, errors: errors}) when errors != [], do: false

  @doc false
  def map_keys(map_data, keys) when is_map(map_data) do
    case List.first(Map.keys(map_data)) do
      nil -> keys
      data when is_atom(data) -> keys
      data when is_binary(data) -> Enum.map(keys, &Atom.to_string(&1))
    end
  end

  def map_keys(_map, keys), do: keys

  def field_status?({{:error, _, _}, _}, status) when status === :error,
    do: true

  def field_status?({{:error, _, _}, _, _}, status) when status === :error,
    do: true

  def field_status?({{field_status, _, _}, _}, status) when field_status === status,
    do: true

  def field_status?({{field_status, _}, _, _}, status) when field_status === status,
    do: true

  def field_status?(_, _), do: false

  def field_value({{:error, _, _}, _} = output), do: output

  def field_value({{:error, _, _}, _, _} = output), do: output

  def field_value({{:ok, _, value}, opts}), do: {value, opts}

  def field_value({{:ok, value}, _, opts}), do: {value, opts}

  def field_value({{:ok, value}, opts}), do: {value, opts}

  def field_value(nil),
    do:
      raise(
        "Oh no!, I think you have not made all the subfields of a conditional field to the same name"
      )
end
