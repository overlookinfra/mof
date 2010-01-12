/*
 * According to appendix A of
 * http://www.dmtf.org/standards/cim/cim_spec_v22
 */

class Mofparser
  prechigh
/*    nonassoc UMINUS */
    left '*' '/'
    left '+' '-'
  preclow

  token PRAGMA IDENTIFIER CLASS ASSOCIATION INDICATION
        AMENDED ENABLEOVERRIDE DISABLEOVERRIDE RESTRICTED TOSUBCLASS TOINSTANCE
	TRANSLATABLE QUALIFIER SCOPE SCHEMA PROPERTY REFERENCE
	METHOD PARAMETER FLAVOR INSTANCE
	AS REF ANY OF
	DT_UINT8 DT_SINT8 DT_UINT16 DT_SINT16 DT_UINT32 DT_SINT32
	DT_UINT64 DT_SINT64 DT_REAL32 DT_REAL64 DT_CHAR16 DT_STR
	DT_BOOL DT_DATETIME
	positiveDecimalValue
	stringValue
	realValue
	charValue
	booleanValue
	nullValue
	binaryValue
	octalValue
	decimalValue
	hexValue
	
rule

  mofSpecification
        : /* empty */
	  { result = @result }
	| mofProduction
	  { result = @result }
	| mofSpecification mofProduction
	  { result = @result }
        ;
	
  mofProduction
        : compilerDirective
	| classDeclaration
	  { @result.classes << val[0] }
	| assocDeclaration
	  { @result.associations << val[0] }
	| indicDeclaration
	  { @result.indications << val[0] }
	| qualifierDeclaration
	  { @result.qualifiers << val[0] }
	| instanceDeclaration
	  { @result.instances << val[0] }
        ;

/***
 * compilerDirective
 *
 */
 
  compilerDirective
	: "#" PRAGMA pragmaName pragmaParameters_opt
	  { case val[2]
              when "include"
		open val[3], :pragma
            end
	    result = nil
          }
        ;

  pragmaName
	: IDENTIFIER
        ;

  pragmaParameters_opt
        : /* empty */
	  { raise StyleError.new(@name,@lineno,@line,"#pragma parameter missing") unless @style == :wmi }
	| "(" pragmaParameterValues ")"
	  { result = val[1] }
	;

  pragmaParameterValues
        : pragmaParameterValue
	| pragmaParameterValues "," pragmaParameterValue
	;

  pragmaParameterValue
        : string
	| integerValue
	  { raise StyleError.new(@name,@lineno,@line,"#pragma parameter missing") unless @style == :wmi }
	| IDENTIFIER
	;

/***
 * classDeclaration
 *
 */
 
  classDeclaration
	: qualifierList_opt CLASS className alias_opt superClass_opt "{" classFeatures "}" ";"
	  { qualifiers = val[0]
	    features = val[6]
	    if qualifiers and qualifiers.include?(:association)
	      # FIXME: 'association' must be first
              # Context:
	      #
	      # The remaining qualifier list must not include
	      # the ASSOCIATION qualifier again. If the
	      # association has no super association, then at
	      # least two references must be specified! The
	      # ASSOCIATION qualifier may be omitted in
	      # sub associations.
	      result = CIM::Schema::Association.new(val[2],qualifiers,val[3],val[4],features)
	    elsif qualifiers and qualifiers.include?(:indication)
	      # FIXME: 'indication' must be first
	      # FIXME: features must not include references
	      result = CIM::Schema::Indication.new(val[2],qualifiers,val[3],val[4],features)
	    else
	      # FIXME: features must not include references
	      result = CIM::Schema::Class.new(val[2],qualifiers,val[3],val[4],features)
	    end
	  }
        ;

  classFeatures
	: /* empty */
	| classFeatures classFeature
	  { result = (val[0]||[]) << val[1] }
        ;

  classFeature
	: propertyDeclaration
	| methodDeclaration
	| referenceDeclaration /* must have association qualifier */
        ;


  qualifierList_opt
	: /* empty */
	| qualifierList
        ;

  qualifierList
	: "[" qualifier qualifiers "]"
	  { result = (val[2]||[])
	    result.unshift val[1] if val[1]
	  }
        ;

  qualifiers
	: /* empty */
	  { result = CIM::Schema::Qualifiers.new }
        | qualifiers "," qualifier
	  { result = val[0]
	    result << val[2] if val[2]
	  }
        ;
	
  qualifier
	: qualifierName qualifierParameter_opt flavor_opt
	  { # Get qualifier decl
	    qualifier = @result.qualifier val[0]
	    raise RbmofError.new(@name,@lineno,@line,"'#{val[0]}' is not a valid qualifier") unless qualifier
	    value = val[1]
	    raise RbmofError.new(@name,@lineno,@line,"#{value.inspect} does not match qualifier type '#{qualifier.type}'") unless qualifier.type.matches?(value)||@style == :wmi
	    # Don't propagate a boolean 'false'
	    if qualifier.type == :bool && value == false
	      result = nil
	    else
	      result = CIM::Schema::Qualifier.new(qualifier,value,val[2])
	    end
	  }
        ;

  flavor_opt
	: /* empty */
	| ":" qflavors
	  { result = val[1] }
        ;

  qflavors
        : flavor
	  { result = [ val[0] ] }
	| qflavors flavor
	  { result = val[0] << val[1] }
	;

  qualifierParameter_opt
	: /* empty */
        | qualifierParameter
        ;

  qualifierParameter
	: "(" constantValue ")"
	  { result = val[1] }
        | arrayInitializer
        ;

  /* CIM::Meta::Flavors */
  flavor
	: AMENDED | ENABLEOVERRIDE | DISABLEOVERRIDE | RESTRICTED | TOSUBCLASS | TRANSLATABLE | TOINSTANCE
	  { case val[0].to_sym
	      when :amended, :toinstance
	        raise StyleError.new(@name,@lineno,@line,"'#{val[0]}' is not a valid flavor") unless @style == :wmi
	    end
	  }
        ;

  alias_opt
	: /* empty */
	| alias
        ;

  superClass_opt
	: /* empty */
	| superClass
        ;

  className
	: IDENTIFIER /* must be <schema>_<classname> in CIM v2.x */
	  { raise ParseError.new("Class name must be prefixed by '<schema>_'") unless val[0].include?("_") || @style == :wmi }
        ;

  alias
	: AS aliasIdentifier
	  { result = val[1] }
        ;

  aliasIdentifier
	: "$" IDENTIFIER /* NO whitespace ! */
	  { result = val[1] }
        ;

  superClass
	: ":" className
	  { result = val[1] }
        ;


  propertyDeclaration
	: qualifierList_opt dataType propertyName array_opt defaultValue_opt ";"
	  { if val[3]
	      type = CIM::Meta::Array.new val[3],val[1]
	    else
	      type = val[1]
	    end
	    result = CIM::Schema::Property.new(type,val[2],val[0],val[4])
	  }
        ;
	
  referenceDeclaration
	: qualifierList_opt objectRef referenceName defaultValue_opt ";"
	  { result = CIM::Schema::Property.new(val[1],val[2],val[0],val[4]) }
        ;

  methodDeclaration
	: qualifierList_opt dataType methodName "(" parameterList_opt ")" ";"
	  { result = CIM::Schema::Method.new(val[1],val[2],val[0],val[4]) }
        ;

  propertyName
	: IDENTIFIER
        ;

  referenceName
	: IDENTIFIER
        ;

  methodName
	: IDENTIFIER
        ;

  dataType
	: DT_UINT8
	| DT_SINT8
	| DT_UINT16
	| DT_SINT16
	| DT_UINT32
	| DT_SINT32
	| DT_UINT64
	| DT_SINT64
	| DT_REAL32
	| DT_REAL64
	| DT_CHAR16
	| DT_STR
	| DT_BOOL
	| DT_DATETIME
        ;

  objectRef
	: className
	  { # WMI uses class names as data types (without REF ?!)
	    raise "Invalid data type" unless @style == :wmi
	    result = CIM::Meta::Reference.new val[0]
	  }

	| className REF
	  { result = CIM::Meta::Reference.new val[0] }
        ;

  parameterList_opt
	: /* empty */
        | parameterList
        ;
	
  parameterList
	: parameter parameters
	  { result = (val[1]||[]).unshift val[0] }
        ;

  parameters
	: /* empty */
	| parameters "," parameter
	  { result = (val[0]||[]) << val[2] }
        ;

  parameter
	: qualifierList_opt typespec parameterName array_opt parameterValue_opt
	  { if val[3]
	      type = CIM::Meta::Array.new val[3], val[1]
	    else
	      type = val[1]
	    end
	    result = CIM::Schema::Property.new(type,val[2],val[0])
	  }
        ;

  typespec
	: dataType
	| objectRef
        ;

  parameterName
	: IDENTIFIER
        ;

  array_opt
	: /* empty */
        | array
        ;

  parameterValue_opt
        : /* empty */
	| defaultValue
	  { raise "Default parameter value not allowed in syntax style '{@style}'" unless @style == :wmi }
	;

  array
	: "[" positiveDecimalValue_opt "]"
	  { result = val[1] }
        ;

  positiveDecimalValue_opt
	: /* empty */
	  { result = -1 }
	| positiveDecimalValue
        ;

  defaultValue_opt
	: /* empty */
        | defaultValue
        ;
	
  defaultValue
	: "=" initializer
	  { result = val[1] }
        ;

  initializer
	: constantValue
	| arrayInitializer
	| referenceInitializer
        ;

  arrayInitializer
	: "{" constantValue constantValues "}"
	  { result = (val[2]||[]).unshift val[1] }
        ;

  constantValues
	: /* empty */
	| constantValues "," constantValue
	  { result = (val[0]||[]) << val[2] }
        ;

  constantValue
	: integerValue
	| realValue
	| charValue
	| string
	| booleanValue
	| nullValue
        ;

  integerValue
	: binaryValue
	| octalValue
	| decimalValue
	| positiveDecimalValue
	| hexValue
        ;

  string
        : stringValue
	| string stringValue
	  { result = val[0] + val[1] }
	;
	
  referenceInitializer
	: objectHandle
	| aliasIdentifier
        ;

  objectHandle
	: namespace_opt modelPath
        ;

  namespace_opt
	: /* empty */
	| namespaceHandle ":"
        ;

  namespaceHandle
	: IDENTIFIER
        ;

  /*
   * Note
	: structure depends on type of namespace
   */

  modelPath
	: className "." keyValuePairList
        ;

  keyValuePairList
	: keyValuePair keyValuePairs
        ;

  keyValuePairs
	: /* empty */
	| keyValuePairs "," keyValuePair
        ;

  keyValuePair
	: keyname "=" initializer
        ;

  keyname
	: propertyName | referenceName
        ;

/***
 * qualifierDeclaration
 *
 */
 
  qualifierDeclaration
          /*      0             1             2     3                 4 */
	: QUALIFIER qualifierName qualifierType scope defaultFlavor_opt ";"
	  { qname = val[1]
	    if qname.is_a?(CIM::Meta::Qualifier)
	      raise "Wrong default type for #{qname}" unless qname.type.matches?(val[2][0])
	      raise "Wrong default value for #{qname}" unless qname.type.matches?(val[2][1])
	      result = qname
	    else
	      result = CIM::Meta::Qualifier.new( val[1], val[2][0], val[2][1], val[3], val[4])
	    end
	  }
        ;

  defaultFlavor_opt
	: /* empty */
	| defaultFlavor
        ;

  qualifierName
	: IDENTIFIER
	| ASSOCIATION /* meta qualifier */
	| INDICATION /* meta qualifier */
	| SCHEMA
        ;

        /* [type, Variant] */
  qualifierType
	: ":" dataType array_opt defaultValue_opt
	  { type = val[2].nil? ? val[1] : CIM::Meta::Array.new(val[2],val[1])
	    result = [ type, val[3] ]
	  }
        ;

  scope
	: "," SCOPE "(" metaElements ")"
	  { result = val[3] }
        ;

  metaElements
	: metaElement
	  { result = CIM::Meta::Scope.new(val[0]) }
	| metaElements "," metaElement
	  { result = val[0] << CIM::Meta::Scope.new(val[2]) }
        ;

  metaElement
	: SCHEMA
	| CLASS
	| ASSOCIATION
	| INDICATION
	| QUALIFIER
	| PROPERTY
	| REFERENCE
	| METHOD
	| PARAMETER
	| ANY
        ;

  defaultFlavor
	: "," FLAVOR "(" flavors ")"
	  { result = val[3] }
        ;

  flavors
	: flavor
	  { result = val[0] }
	| flavors "," flavor
	  { result = val[0] << val[2] }
        ;

/***
 * instanceDeclaration
 *
 */
 
  instanceDeclaration
	: qualifierList_opt INSTANCE OF className alias_opt "{" valueInitializers "}" ";"
        ;

  valueInitializers
        : valueInitializer
        | valueInitializers valueInitializer
        ;

  valueInitializer
	: qualifierList_opt keyname "=" initializer ";"
        ;

end

---- header ----

# rbmof.rb - generated by racc

require 'strscan'
require File.dirname(__FILE__) + '/mofscanner'
require File.dirname(__FILE__) + '/rbmof_io'
require File.dirname(__FILE__) + '/../../rbcim/rbcim'
require File.dirname(__FILE__) + '/result'

require 'pathname'

module CIM
module Schema

# to be used to flag @style issues
class RbmofError < ::SyntaxError
  attr_reader :name, :lineno, :line, :msg
  def initialize name, lineno, line, msg
    @name,@lineno,@line,@msg = name, lineno, line, msg
  end
  def to_s
    "#{@name}:#{@lineno}: #{line}\n#{msg}"
  end
end

class ScannerError < RbmofError
  def initialize name, lineno, line, msg
    super name,lineno,line,"Unrecognized '#{msg}'"
  end
end

class ParserError < RbmofError
  attr_reader :line, :token, :token_value, :stack
  def initialize name, lineno, line, token, token_value, stack
    @token,@token_value,@stack = token, token_value, stack
    super name,lineno,line,""
  end
  def to_s
    ret = "#{super}\tnear token #{@token_value.inspect}\n"
    ret << "\tStack [#{@stack.size}]:\n"
    idx = stack.size-1
    (1..12).each do |i|
      s = stack[idx]
      case s
        when String, NilClass: s = s.inspect
      else
	s = s.to_s
      end
      if s.size > 80
	ret << "[#{i}]\t#{s[0,80]}..."
      else
	ret << "[#{i}]\t#{s}"
      end
      ret << "\n"
      idx -= 1
      break if idx < 0
    end
    ret
  end
end

class StyleError < RbmofError
end

---- inner ----

include Mofscanner

include Rbmof_IO

def style
  @style
end
---- footer ----

require File.dirname(__FILE__) + '/rbmof_main'

end # Schema
end # CIM

