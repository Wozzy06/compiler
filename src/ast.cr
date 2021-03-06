require "./errors"
require "./location"
require "./mangler"
require "./type"

module Runic
  module AST
    module Literal
    end

    module TopLevel
      @visited = Atomic(Int32).new(0)

      def visited?
        _, changed = @visited.compare_and_set(0, 1)
        !changed
      end
    end

    abstract class Node
      getter location : Location
      @type : Type?

      def initialize(@location)
      end

      def type? : Type?
        if type = @type
          type
        elsif type = resolve_type
          @type = Type.new(type)
        end
      end

      def type : Type
        type? || raise SemanticError.new("expected #{self} to have a type but it doesn't.", location)
      end

      def type=(type : String | Type | Nil)
        @type = Type.new(type) if type
      end

      private abstract def resolve_type : Type

      {% for method in %w(primitive void bool integer unsigned signed float) %}
        def {{method.id}}?
          if type == type?
            type.{{method.id}}?
          else
            false
          end
        end
      {% end %}
    end

    abstract class Number < Node
      include Literal

      getter value : String
      property sign : String?

      def self.new(token : Token, type = token.literal_type)
        new(token.value, token.location, type)
      end

      def initialize(@value, @location, type = nil)
        @type = Type.new(type) if type
      end

      def negative
        sign == "-"
      end

      def signed?
        type.signed?
      end

      def unsigned?
        type.unsigned?
      end
    end

    class Integer < Number
      MAX_UINT8 = "255"
      MAX_UINT16 = "65535"
      MAX_UINT32 = "4294967295"
      MAX_UINT64 = "18446744073709551615"
      MAX_UINT128 = "340282366920938463463374607431768211455"

      MIN_INT8 = "128"
      MAX_INT8 = "127"
      MIN_INT16 = "32768"
      MAX_INT16 = "32767"
      MIN_INT32 = "2147483648"
      MAX_INT32 = "2147483647"
      MIN_INT64 = "9223372036854775808"
      MAX_INT64 = "9223372036854775807"
      MIN_INT128 = "170141183460469231731687303715884105728"
      MAX_INT128 = "170141183460469231731687303715884105727"

      MAX_OCTAL_UINT8 = "0o377"
      MAX_OCTAL_UINT16 = "0o177777"
      MAX_OCTAL_UINT32 = "0o37777777777"
      MAX_OCTAL_UINT64 = "0o1777777777777777777777"
      MAX_OCTAL_UINT128 = "0o3777777777777777777777777777777777777777777"

      MIN_OCTAL_INT8 = "0o200"
      MAX_OCTAL_INT8 = "0o177"
      MIN_OCTAL_INT16 = "0o100000"
      MAX_OCTAL_INT16 = "0o77777"
      MIN_OCTAL_INT32 = "0o20000000000"
      MAX_OCTAL_INT32 = "0o17777777777"
      MIN_OCTAL_INT64 = "0o1000000000000000000000"
      MAX_OCTAL_INT64 = "0o777777777777777777777"
      MIN_OCTAL_INT128 = "0o2000000000000000000000000000000000000000000"
      MAX_OCTAL_INT128 = "0o1777777777777777777777777777777777777777777"

      def radix
        case value
        when .starts_with?("0x") then 16
        when .starts_with?("0o") then 8
        when .starts_with?("0b") then 2
        else                          10
        end
      end

      private def resolve_type
        case @value
        when .starts_with?("0x") then infer_hexadecimal_type
        when .starts_with?("0b") then infer_binary_type
        when .starts_with?("0o") then infer_octal_type
        else                          infer_decimal_type
        end
      end

      private def infer_hexadecimal_type
        if @value.size <= 10
          "u32"
        elsif @value.size <= 18
          "u64"
        elsif @value.size <= 34
          "u128"
        end
      end

      private def infer_binary_type
        if @value.size <= 34
          "u32"
        elsif @value.size <= 66
          "u64"
        elsif @value.size <= 130
          "u128"
        end
      end

      private def infer_octal_type
        if compare(negative ? MIN_OCTAL_INT32 : MAX_OCTAL_INT32)
          "i32"
        elsif compare(negative ? MIN_OCTAL_INT64 : MAX_OCTAL_INT64)
          "i64"
        elsif compare(negative ? MIN_OCTAL_INT128 : MAX_OCTAL_INT128)
          "i128"
        end
      end

      private def infer_decimal_type
        if compare(negative ? MIN_INT32 : MAX_INT32)
          "i32"
        elsif compare(negative ? MIN_INT64 : MAX_INT64)
          "i64"
        elsif compare(negative ? MIN_INT128 : MAX_INT128)
          "i128"
        end
      end

      def valid_type_definition?
        case @value
        when .starts_with?("0x") then valid_hexadecimal_type?
        when .starts_with?("0b") then valid_binary_type?
        when .starts_with?("0o") then valid_octal_type?
        else                          valid_decimal_type?
        end
      end

      private def valid_hexadecimal_type?
        case type?.try(&.name)
        when "u8"   then @value.size <= (2+2)
        when "u16"  then @value.size <= (2+4)
        when "u32"  then @value.size <= (2+8)
        when "u64"  then @value.size <= (2+16)
        when "u128" then @value.size <= (2+32)
        when "i8"   then compare("0x7f", downcase: true)
        when "i16"  then compare("0x7fff", downcase: true)
        when "i32"  then compare("0x7fffffff", downcase: true)
        when "i64"  then compare("0x7fffffffffffffff", downcase: true)
        when "i128" then compare("0x7fffffffffffffffffffffffffffffff", downcase: true)
        end
      end

      private def valid_binary_type?
        case type?.try(&.name)
        when "u8"   then @value.size <= 2+8
        when "u16"  then @value.size <= 2+16
        when "u32"  then @value.size <= 2+32
        when "u64"  then @value.size <= 2+64
        when "u128" then @value.size <= 2+128
        when "i8"   then @value.size <= 2+7
        when "i16"  then @value.size <= 2+15
        when "i32"  then @value.size <= 2+31
        when "i64"  then @value.size <= 2+63
        when "i128" then @value.size <= 2+127
        end
      end

      private def valid_octal_type?
        case type?.try(&.name)
        when "i8"   then compare(negative ? MIN_OCTAL_INT8 : MAX_OCTAL_INT8)
        when "i16"  then compare(negative ? MIN_OCTAL_INT16 : MAX_OCTAL_INT16)
        when "i32"  then compare(negative ? MIN_OCTAL_INT32 : MAX_OCTAL_INT32)
        when "i64"  then compare(negative ? MIN_OCTAL_INT64 : MAX_OCTAL_INT64)
        when "i128" then compare(negative ? MIN_OCTAL_INT128 : MAX_OCTAL_INT128)
        when "u8"   then compare(MAX_OCTAL_UINT8)
        when "u16"  then compare(MAX_OCTAL_UINT16)
        when "u32"  then compare(MAX_OCTAL_UINT32)
        when "u64"  then compare(MAX_OCTAL_UINT64)
        when "u128" then compare(MAX_OCTAL_UINT128)
        end
      end

      private def valid_decimal_type?
        case type?.try(&.name)
        when "i8"   then compare(negative ? MIN_INT8 : MAX_INT8)
        when "i16"  then compare(negative ? MIN_INT16 : MAX_INT16)
        when "i32"  then compare(negative ? MIN_INT32 : MAX_INT32)
        when "i64"  then compare(negative ? MIN_INT64 : MAX_INT64)
        when "i128" then compare(negative ? MIN_INT128 : MAX_INT128)
        when "u8"   then compare(MAX_UINT8)
        when "u16"  then compare(MAX_UINT16)
        when "u32"  then compare(MAX_UINT32)
        when "u64"  then compare(MAX_UINT64)
        when "u128" then compare(MAX_UINT128)
        end
      end

      private def compare(other, downcase = false)
        value = downcase ? @value.downcase : @value
        value.size < other.size ||
          (value.size == other.size && value <= other)
      end
    end

    class Float < Number
      private def resolve_type
        "f64"
      end
    end

    class Boolean < Node
      include Literal

      getter value : String

      def self.new(token : Token)
        new(token.value, token.location)
      end

      def initialize(@value, @location)
      end

      private def resolve_type
        "bool"
      end
    end

    class Constant < Node
      include TopLevel

      getter name : String

      def self.new(token : Token)
        new(token.value, token.location)
      end

      def initialize(@name, @location)
      end

      private def resolve_type
        # can't be determined (need semantic analysis)
      end
    end

    class ConstantDefinition < Node
      include TopLevel

      getter name : String
      getter value : AST::Node # AST::Literal

      def initialize(@name, @value, @location)
      end

      private def resolve_type
        value.type?
      end
    end

    class Variable < Node
      @name : String
      property shadow : Int32

      def self.new(token : Token)
        new(token.value, nil, token.location)
      end

      def initialize(@name, @type, @location)
        @shadow = 0
      end

      def name
        if shadow > 0
          "__runic_shadow_#{@name}#{@shadow}"
        else
          @name
        end
      end

      def original_name
        @name
      end

      private def resolve_type
        # can't be determined (need semantic analysis)
      end
    end

    class Argument < Variable
      getter default : Literal?

      def initialize(name, type, @default, location)
        super(name, nil, location)
        self.type = type if type
      end

      def resolve_type
        @default.try(&.type?)
      end
    end

    class Binary < Node
      property operator : String
      getter lhs : Node
      property rhs : Node

      def self.new(token : Token, lhs, rhs)
        new(token.value, lhs, rhs, token.location)
      end

      def initialize(@operator, @lhs, @rhs, @location)
      end

      def assignment?
        OPERATORS::ASSIGNMENT.includes?(operator)
      end

      def logical?
        OPERATORS::LOGICAL.includes?(operator)
      end

      private def resolve_type
        if lhs.type? && rhs.type?
          INTRINSICS.resolve(operator, lhs.type, rhs.type)
        end
      end
    end

    class Unary < Node
      getter operator : String
      getter expression : Node

      def self.new(token : Token, expression)
        new(token.value, expression, token.location)
      end

      def initialize(@operator, @expression, @location)
      end

      private def resolve_type
        type = INTRINSICS.resolve(operator, expression.type)
        Type.new(type) if type
      end
    end

    class Body < Node
      include Indexable(Node)
      # include Enumerable(Node)

      getter expressions : Array(Node)

      def initialize(@expressions, @location)
      end

      def each
        expressions.each { |node| yield node }
      end

      def <<(node : AST::Node)
        expressions << node
      end

      def unsafe_at(i)
        expressions.unsafe_at(i)
      end

      def resolve_type
        expressions.last?.try(&.type?)
      end
    end

    class Prototype < Node
      include TopLevel

      property name : String
      getter args : Array(Argument)
      getter documentation : String

      def initialize(@name, @args, type, @documentation, @location)
        @type = Type.new(type) if type
      end

      def mangled_name
        name == "main" ? name : Mangler.mangle(self)
      end

      def arg_count
        min, max = 0, args.size

        args.each do |arg|
          break if arg.default
          min += 1
        end

        min..max
      end

      def resolve_type
        # extern: unreachable
      end

      def matches?(other : Prototype)
        type == other.type &&
          args.equals?(other.args) { |a, b| a.type == b.type }
      end
    end

    class Function < Node
      include TopLevel

      getter prototype : Prototype
      getter attributes : Array(String)
      getter body : Body

      def initialize(@prototype, @attributes, @body, @location)
      end

      def matches?(other : AST::Function)
        args.equals?(other.args) { |a, b| a.type == b.type }
      end

      def name
        prototype.name
      end

      def mangled_name
        prototype.mangled_name
      end

      def args
        prototype.args
      end

      def attribute?(name : String)
        attributes.includes?(name)
      end

      def resolve_type
        prototype.type? || body.type?
      end
    end

    class Call < Node
      getter receiver : Node?
      getter callee : String
      getter args : Array(Node)
      getter kwargs : Hash(String, Node)
      property prototype : Prototype?

      def self.new(receiver : Node?, identifier : Token, args, kwargs)
        new(receiver, identifier.value, args, kwargs, identifier.location)
      end

      def initialize(@receiver, @callee, @args, @kwargs, @location)
      end

      def resolve_type
        # can't be determined (need semantic analysis)
      end

      def mangled_callee
        @prototype.not_nil!.mangled_name
      end

      def to_s(io : IO)
        if receiver = @receiver
          io << receiver.type.name
          io << '#'
        end

        io << @callee

        io << '('
        @args.each_with_index do |arg, index|
          if receiver
            next if index == 0
            io << ", " unless index == 1
          else
            io << ", " unless index == 0
          end
          io << arg.type.name
        end
        io << ')'
      end
    end

    class If < Node
      getter condition : Node
      getter body : Body
      getter alternative : Body?

      def initialize(@condition, @body, @alternative, @location)
      end

      def resolve_type
        # could be determined, but we postpone to semantic analysis
      end
    end

    class Unless < Node
      getter condition : Node
      getter body : Body

      def initialize(@condition, @body, @location)
      end

      def resolve_type
        # could be determined, but we postpone to semantic analysis
        # currently sets it to "void" until we support nilables
      end
    end

    class While < Node
      getter condition : Node
      getter body : Body

      def initialize(@condition, @body, @location)
      end

      def resolve_type
        "void"
      end
    end

    class Until < Node
      getter condition : Node
      getter body : Body

      def initialize(@condition, @body, @location)
      end

      def resolve_type
        "void"
      end
    end

    class When < Node
      getter conditions : Array(Node)
      getter body : Body

      def initialize(@conditions, @body, @location)
      end

      def resolve_type
        body.last?.try(&.type)
      end
    end

    class Case < Node
      getter value : Node
      getter cases : Array(When)
      getter alternative : Body?

      def initialize(@value, @cases, @alternative, @location)
      end

      def resolve_type
        # could be determined, but postpone to semantic analysis
      end
    end

    class Struct < Node
      include TopLevel

      getter name : String
      getter attributes : Array(String)
      getter methods
      getter locations : Array(Location)
      getter documentation : String

      # TODO: should be an Array(AST::Prototype)
      # TODO: should be defined on struct Type (?)
      getter prototypes

      def initialize(@name, @attributes, @documentation, @location)
        @methods = [] of AST::Function
        @prototypes = {} of String => AST::Prototype
        @locations = [@location]
      end

      def attribute?(name : String)
        attributes.includes?(name)
      end

      def resolve_type
        # N/A
      end
    end
  end
end
