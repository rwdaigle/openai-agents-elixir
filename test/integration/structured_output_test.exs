defmodule OpenAI.Agents.Integration.StructuredOutputTest do
  use ExUnit.Case, async: false
  @moduletag :remote

  # First, let's create the schema modules
  defmodule WeatherReport do
    use Ecto.Schema
    import Ecto.Changeset
    
    embedded_schema do
      field :temperature, :integer
      field :conditions, :string
      field :humidity, :integer
      field :wind_speed, :float
    end
    
    def changeset(attrs) do
      %__MODULE__{}
      |> cast(attrs, [:temperature, :conditions, :humidity, :wind_speed])
      |> validate_required([:temperature, :conditions])
      |> validate_number(:humidity, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    end
    
    def json_schema do
      %{
        type: "object",
        properties: %{
          temperature: %{type: "integer", description: "Temperature in Fahrenheit"},
          conditions: %{type: "string", description: "Weather conditions"},
          humidity: %{type: "integer", minimum: 0, maximum: 100},
          wind_speed: %{type: "number", description: "Wind speed in mph"}
        },
        required: ["temperature", "conditions", "humidity", "wind_speed"],
        additionalProperties: false
      }
    end
  end

  defmodule BookRecommendation do
    use Ecto.Schema
    import Ecto.Changeset
    
    embedded_schema do
      field :title, :string
      field :author, :string
      field :genre, :string
      field :reason, :string
      field :rating, :float
    end
    
    def changeset(attrs) do
      %__MODULE__{}
      |> cast(attrs, [:title, :author, :genre, :reason, :rating])
      |> validate_required([:title, :author, :reason])
      |> validate_number(:rating, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    end
    
    def json_schema do
      %{
        type: "object",
        properties: %{
          title: %{type: "string"},
          author: %{type: "string"},
          genre: %{type: "string"},
          reason: %{type: "string", description: "Why this book is recommended"},
          rating: %{type: "number", minimum: 0, maximum: 5}
        },
        required: ["title", "author", "genre", "reason", "rating"],
        additionalProperties: false
      }
    end
  end

  defmodule TaskList do
    use Ecto.Schema
    import Ecto.Changeset
    
    embedded_schema do
      field :tasks, {:array, :map}
      field :total_time_estimate, :integer
      field :difficulty, :string
    end
    
    def changeset(attrs) do
      %__MODULE__{}
      |> cast(attrs, [:tasks, :total_time_estimate, :difficulty])
      |> validate_required([:tasks])
    end
    
    def json_schema do
      %{
        type: "object",
        properties: %{
          tasks: %{
            type: "array",
            items: %{
              type: "object",
              properties: %{
                name: %{type: "string"},
                duration_minutes: %{type: "integer"},
                priority: %{type: "string", enum: ["high", "medium", "low"]}
              },
              required: ["name", "duration_minutes", "priority"],
              additionalProperties: false
            }
          },
          total_time_estimate: %{type: "integer", description: "Total time in minutes"},
          difficulty: %{type: "string", enum: ["easy", "medium", "hard"]}
        },
        required: ["tasks", "total_time_estimate", "difficulty"],
        additionalProperties: false
      }
    end
  end

  # Now the agents
  defmodule WeatherAgent do
    use OpenAI.Agent
    
    @impl true
    def configure do
      %{
        name: "weather_agent",
        instructions: "Provide weather information in the requested format.",
        output_schema: WeatherReport
      }
    end
  end

  defmodule BookAgent do
    use OpenAI.Agent
    
    @impl true
    def configure do
      %{
        name: "book_agent",
        instructions: "You are a book recommendation expert. Provide book recommendations.",
        output_schema: BookRecommendation
      }
    end
  end

  defmodule TaskPlannerAgent do
    use OpenAI.Agent
    
    @impl true
    def configure do
      %{
        name: "task_planner",
        instructions: "You are a task planning assistant. Break down requests into specific tasks.",
        output_schema: TaskList
      }
    end
  end

  describe "structured output with schemas" do
    @tag :remote
    test "weather agent returns structured weather data" do
      {:ok, result} = OpenAI.Agents.run(
        WeatherAgent, 
        "What's the weather like in San Francisco today? Make it sunny and mild."
      )
      
      # Parse the JSON output
      {:ok, weather_data} = Jason.decode(result.output)
      
      # Validate structure
      assert weather_data["temperature"]
      assert weather_data["conditions"]
      assert is_integer(weather_data["temperature"])
      assert is_binary(weather_data["conditions"])
      
      # Should mention sunny as requested
      assert String.contains?(String.downcase(weather_data["conditions"]), ["sun", "clear", "fair"])
    end

    @tag :remote
    test "book agent returns structured recommendation" do
      {:ok, result} = OpenAI.Agents.run(
        BookAgent,
        "Recommend a science fiction book about space exploration"
      )
      
      {:ok, book_data} = Jason.decode(result.output)
      
      # Validate required fields
      assert book_data["title"]
      assert book_data["author"]
      assert book_data["reason"]
      
      # Genre should be science fiction
      if book_data["genre"] do
        assert String.contains?(String.downcase(book_data["genre"]), ["sci", "fiction"])
      end
      
      # Should have a rating if provided
      if book_data["rating"] do
        assert book_data["rating"] >= 0 and book_data["rating"] <= 5
      end
    end

    @tag :remote
    test "task planner returns structured task list" do
      {:ok, result} = OpenAI.Agents.run(
        TaskPlannerAgent,
        "Plan tasks for organizing a small birthday party"
      )
      
      {:ok, task_data} = Jason.decode(result.output)
      
      # Validate structure
      assert is_list(task_data["tasks"])
      assert length(task_data["tasks"]) > 0
      
      # Each task should have required fields
      Enum.each(task_data["tasks"], fn task ->
        assert task["name"]
      end)
      
      # Optional fields
      if task_data["total_time_estimate"] do
        assert is_integer(task_data["total_time_estimate"])
      end
      
      if task_data["difficulty"] do
        assert task_data["difficulty"] in ["easy", "medium", "hard"]
      end
    end
  end

  describe "validation and error handling" do
    defmodule StrictWeatherAgent do
      use OpenAI.Agent
      
      @impl true
      def configure do
        %{
          name: "strict_weather_agent",
          instructions: "Provide weather data. Temperature must be between -50 and 150 Fahrenheit.",
          output_schema: WeatherReport
        }
      end
    end

    @tag :remote
    test "agent respects schema constraints" do
      {:ok, result} = OpenAI.Agents.run(
        StrictWeatherAgent,
        "What's the weather in Antarctica?"
      )
      
      {:ok, weather_data} = Jason.decode(result.output)
      
      # Temperature should be reasonable even for Antarctica
      assert weather_data["temperature"] >= -50
      assert weather_data["temperature"] <= 150
      
      # Humidity should be valid
      if weather_data["humidity"] do
        assert weather_data["humidity"] >= 0
        assert weather_data["humidity"] <= 100
      end
    end
  end

  describe "complex nested schemas" do
    defmodule RecipeSchema do
      use Ecto.Schema
      
        embedded_schema do
        field :name, :string
        field :cuisine, :string
        field :prep_time_minutes, :integer
        field :ingredients, {:array, :map}
        field :steps, {:array, :string}
        field :servings, :integer
      end
      
      def json_schema do
        %{
          type: "object",
          properties: %{
            name: %{type: "string"},
            cuisine: %{type: "string"},
            prep_time_minutes: %{type: "integer"},
            ingredients: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{
                  name: %{type: "string"},
                  amount: %{type: "string"},
                  unit: %{type: "string"}
                },
                required: ["name", "amount", "unit"],
                additionalProperties: false
              }
            },
            steps: %{
              type: "array",
              items: %{type: "string"}
            },
            servings: %{type: "integer"}
          },
          required: ["name", "cuisine", "prep_time_minutes", "ingredients", "steps", "servings"],
          additionalProperties: false
        }
      end
    end

    defmodule RecipeAgent do
      use OpenAI.Agent
      
      @impl true
      def configure do
        %{
          name: "recipe_agent",
          instructions: "You are a chef. Provide recipes in the specified format.",
          output_schema: RecipeSchema
        }
      end
    end

    @tag :remote
    test "agent handles complex nested schemas" do
      {:ok, result} = OpenAI.Agents.run(
        RecipeAgent,
        "Give me a simple pasta recipe"
      )
      
      {:ok, recipe_data} = Jason.decode(result.output)
      
      # Validate structure
      assert recipe_data["name"]
      assert is_list(recipe_data["ingredients"])
      assert is_list(recipe_data["steps"])
      
      # Validate ingredients structure
      assert length(recipe_data["ingredients"]) > 0
      
      Enum.each(recipe_data["ingredients"], fn ingredient ->
        assert ingredient["name"]
        assert ingredient["amount"]
      end)
      
      # Should have multiple steps
      assert length(recipe_data["steps"]) > 0
      
      # Each step should be a string
      Enum.each(recipe_data["steps"], fn step ->
        assert is_binary(step)
      end)
    end
  end
end