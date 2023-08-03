defmodule MishkaDeveloperTools.Helper.Derive do
  alias MishkaDeveloperTools.Helper.Derive.{Parser, SanitizerDerive, ValidationDerive}

  def derive({:error, _, _} = error, _derive_input), do: error

  def derive({:ok, data}, derive_inputs) do
    reduced_fields =
      Enum.reduce(derive_inputs, %{}, fn map, acc ->
        parsed_derive = Parser.parser(map.derive)
        get_field = Map.get(data, map.field)

        if !is_nil(get_field) do
          {all_data, validated_errors} =
            {map.field, get_field}
            |> SanitizerDerive.call(Map.get(parsed_derive, :sanitize))
            |> ValidationDerive.call(Map.get(parsed_derive, :validate))

          converted_validated_values =
            if length(validated_errors) > 0, do: {:error, validated_errors}, else: all_data

          Map.put(acc, map.field, converted_validated_values)
        else
          acc
        end
      end)

    {:error, :bad_parameters, get_error} = error = error_handler(reduced_fields)

    if length(get_error) == 0, do: {:ok, Map.merge(data, reduced_fields)}, else: error
  end

  def error_handler(reduced_fields) do
    get_error =
      reduced_fields
      |> Map.values()
      |> Enum.filter(&(is_tuple(&1) && elem(&1, 0) == :error))
      |> Enum.map(fn {:error, errors} -> errors end)
      |> Enum.concat()

    {:error, :bad_parameters, get_error}
  end
end