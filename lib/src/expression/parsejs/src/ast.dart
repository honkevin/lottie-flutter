library ast;

part 'ast_visitor.dart';

// AST structure mostly designed after the Mozilla Parser API:
//  https://developer.mozilla.org/en-US/docs/Mozilla/Projects/SpiderMonkey/Parser_API

/// A node in the abstract syntax tree of a JavaScript program.
abstract class Node {
  /// The parent of this node, or null if this is the [Program] node.
  ///
  /// If you transform the AST in any way, it is your own responsibility to update parent pointers accordingly.
  Node parent;

  /// Source-code offset.
  int start, end;

  /// 1-based line number.
  int line;

  /// Retrieves the filename from the enclosing [Program]. Returns null if the node is orphaned.
  String get filename {
    Program program = enclosingProgram;
    if (program != null) return program.filename;
    return null;
  }

  /// A string with filename and line number.
  String get location => "$filename:$line";

  /// Returns the [Program] node enclosing this node, possibly the node itself, or null if not enclosed in any program.
  Program get enclosingProgram {
    Node node = this;
    while (node != null) {
      if (node is Program) return node;
      node = node.parent;
    }
    return null;
  }

  /// Returns the [FunctionNode] enclosing this node, possibly the node itself, or null if not enclosed in any function.
  FunctionNode get enclosingFunction {
    Node node = this;
    while (node != null) {
      if (node is FunctionNode) return node;
      node = node.parent;
    }
    return null;
  }

  /// Visits the immediate children of this node.
  void forEach(void callback(Node node));

  /// Calls the relevant `visit` method on the visitor.
  T visitBy<T>(Visitor<T> visitor);

  /// Calls the relevant `visit` method on the visitor.
  T visitBy1<T, A>(Visitor1<T, A> visitor, A arg);
}

/// Superclass for [Program], [FunctionNode], and [CatchClause], which are the three types of node that
/// can host local variables.
abstract class Scope extends Node {
  /// Variables declared in this scope, including the implicitly declared "arguments" variable.
  Set<String> environment;
}

/// A collection of [Program] nodes.
///
/// This node is not generated by the parser, but is a convenient way to cluster multiple ASTs into a single AST,
/// should you wish to do so.
class Programs extends Node {
  List<Program> programs = <Program>[];

  Programs(this.programs);

  void forEach(callback) => programs.forEach(callback);

  String toString() => 'Programs';

  visitBy<T>(Visitor<T> v) => v.visitPrograms(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitPrograms(this, arg);
}

/// The root node of a JavaScript AST, representing the top-level scope.
class Program extends Scope {
  /// Indicates where the program was parsed from.
  /// In principle, this can be anything, it is just a string passed to the parser for convenience.
  String filename;

  List<Statement> body;

  Program(this.body);

  void forEach(callback) => body.forEach(callback);

  String toString() => 'Program';

  visitBy<T>(Visitor<T> v) => v.visitProgram(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitProgram(this, arg);
}

/// A function, which may occur as a function expression, function declaration, or property accessor in an object literal.
class FunctionNode extends Scope {
  Name name;
  List<Name> params;
  Statement body;

  FunctionNode(this.name, this.params, this.body);

  bool get isExpression => parent is FunctionExpression;
  bool get isDeclaration => parent is FunctionDeclaration;
  bool get isAccessor => parent is Property && (parent as Property).isAccessor;

  forEach(callback) {
    if (name != null) callback(name);
    params.forEach(callback);
    callback(body);
  }

  String toString() => 'FunctionNode';

  visitBy<T>(Visitor<T> v) => v.visitFunctionNode(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitFunctionNode(this, arg);
}

/// Mention of a variable, property, or label.
class Name extends Node {
  /// Name being referenced.
  ///
  /// Unicode values have been resolved.
  String value;

  /// Link to the enclosing [FunctionExpression], [Program], or [CatchClause] where this variable is declared
  /// (defaults to [Program] if undeclared), or `null` if this is not a variable.
  Scope scope;

  /// True if this refers to a variable name.
  bool get isVariable =>
      parent is NameExpression ||
      parent is FunctionNode ||
      parent is VariableDeclarator ||
      parent is CatchClause;

  /// True if this refers to a property name.
  bool get isProperty =>
      (parent is MemberExpression &&
          (parent as MemberExpression).property == this) ||
      (parent is Property && (parent as Property).key == this);

  /// True if this refers to a label name.
  bool get isLabel =>
      parent is BreakStatement ||
      parent is ContinueStatement ||
      parent is LabeledStatement;

  Name(this.value);

  void forEach(callback) {}

  String toString() => '$value';

  visitBy<T>(Visitor<T> v) => v.visitName(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitName(this, arg);
}

/// Superclass for all nodes that are statements.
abstract class Statement extends Node {}

/// Statement of form: `;`
class EmptyStatement extends Statement {
  void forEach(callback) {}

  String toString() => 'EmptyStatement';

  visitBy<T>(Visitor<T> v) => v.visitEmptyStatement(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitEmptyStatement(this, arg);
}

/// Statement of form: `{ [body] }`
class BlockStatement extends Statement {
  List<Statement> body;

  BlockStatement(this.body);

  void forEach(callback) => body.forEach(callback);

  String toString() => 'BlockStatement';

  visitBy<T>(Visitor<T> v) => v.visitBlock(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitBlock(this, arg);
}

/// Statement of form: `[expression];`
class ExpressionStatement extends Statement {
  Expression expression;

  ExpressionStatement(this.expression);

  forEach(callback) => callback(expression);

  String toString() => 'ExpressionStatement';

  visitBy<T>(Visitor<T> v) => v.visitExpressionStatement(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitExpressionStatement(this, arg);
}

/// Statement of form: `if ([condition]) then [then] else [otherwise]`.
class IfStatement extends Statement {
  Expression condition;
  Statement then;
  Statement otherwise; // May be null.

  IfStatement(this.condition, this.then, [this.otherwise]);

  forEach(callback) {
    callback(condition);
    callback(then);
    if (otherwise != null) callback(otherwise);
  }

  String toString() => 'IfStatement';

  visitBy<T>(Visitor<T> v) => v.visitIf(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitIf(this, arg);
}

/// Statement of form: `[label]: [body]`
class LabeledStatement extends Statement {
  Name label;
  Statement body;

  LabeledStatement(this.label, this.body);

  forEach(callback) {
    callback(label);
    callback(body);
  }

  String toString() => 'LabeledStatement';

  visitBy<T>(Visitor<T> v) => v.visitLabeledStatement(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitLabeledStatement(this, arg);
}

/// Statement of form: `break;` or `break [label];`
class BreakStatement extends Statement {
  Name label; // May be null.

  BreakStatement(this.label);

  forEach(callback) {
    if (label != null) callback(label);
  }

  String toString() => 'BreakStatement';

  visitBy<T>(Visitor<T> v) => v.visitBreak(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitBreak(this, arg);
}

/// Statement of form: `continue;` or `continue [label];`
class ContinueStatement extends Statement {
  Name label; // May be null.

  ContinueStatement(this.label);

  forEach(callback) {
    if (label != null) callback(label);
  }

  String toString() => 'ContinueStatement';

  visitBy<T>(Visitor<T> v) => v.visitContinue(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitContinue(this, arg);
}

/// Statement of form: `with ([object]) { [body] }`
class WithStatement extends Statement {
  Expression object;
  Statement body;

  WithStatement(this.object, this.body);

  forEach(callback) {
    callback(object);
    callback(body);
  }

  String toString() => 'WithStatement';

  visitBy<T>(Visitor<T> v) => v.visitWith(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitWith(this, arg);
}

/// Statement of form: `switch ([argument]) { [cases] }`
class SwitchStatement extends Statement {
  Expression argument;
  List<SwitchCase> cases;

  SwitchStatement(this.argument, this.cases);

  forEach(callback) {
    callback(argument);
    cases.forEach(callback);
  }

  String toString() => 'SwitchStatement';

  visitBy<T>(Visitor<T> v) => v.visitSwitch(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitSwitch(this, arg);
}

/// Clause in a switch: `case [expression]: [body]` or `default: [body]` if [expression] is null.
class SwitchCase extends Node {
  Expression expression; // May be null (for default clause)
  List<Statement> body;

  SwitchCase(this.expression, this.body);
  SwitchCase.defaultCase(this.body);

  /// True if this is a default clause, and not a case clause.
  bool get isDefault => expression == null;

  forEach(callback) {
    if (expression != null) callback(expression);
    body.forEach(callback);
  }

  String toString() => 'SwitchCase';

  visitBy<T>(Visitor<T> v) => v.visitSwitchCase(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitSwitchCase(this, arg);
}

/// Statement of form: `return [argument];` or `return;`
class ReturnStatement extends Statement {
  Expression argument;

  ReturnStatement(this.argument);

  forEach(callback) => argument != null ? callback(argument) : null;

  String toString() => 'ReturnStatement';

  visitBy<T>(Visitor<T> v) => v.visitReturn(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitReturn(this, arg);
}

/// Statement of form: `throw [argument];`
class ThrowStatement extends Statement {
  Expression argument;

  ThrowStatement(this.argument);

  forEach(callback) => callback(argument);

  String toString() => 'ThrowStatement';

  visitBy<T>(Visitor<T> v) => v.visitThrow(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitThrow(this, arg);
}

/// Statement of form: `try [block] catch [handler] finally [finalizer]`.
class TryStatement extends Statement {
  BlockStatement block;
  CatchClause handler; // May be null
  BlockStatement finalizer; // May be null (but not if handler is null)

  TryStatement(this.block, this.handler, this.finalizer);

  forEach(callback) {
    callback(block);
    if (handler != null) callback(handler);
    if (finalizer != null) callback(finalizer);
  }

  String toString() => 'TryStatement';

  visitBy<T>(Visitor<T> v) => v.visitTry(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitTry(this, arg);
}

/// A catch clause: `catch ([param]) [body]`
class CatchClause extends Scope {
  Name param;
  BlockStatement body;

  CatchClause(this.param, this.body);

  forEach(callback) {
    callback(param);
    callback(body);
  }

  String toString() => 'CatchClause';

  visitBy<T>(Visitor<T> v) => v.visitCatchClause(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitCatchClause(this, arg);
}

/// Statement of form: `while ([condition]) [body]`
class WhileStatement extends Statement {
  Expression condition;
  Statement body;

  WhileStatement(this.condition, this.body);

  forEach(callback) {
    callback(condition);
    callback(body);
  }

  String toString() => 'WhileStatement';

  visitBy<T>(Visitor<T> v) => v.visitWhile(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitWhile(this, arg);
}

/// Statement of form: `do [body] while ([condition]);`
class DoWhileStatement extends Statement {
  Statement body;
  Expression condition;

  DoWhileStatement(this.body, this.condition);

  forEach(callback) {
    callback(body);
    callback(condition);
  }

  String toString() => 'DoWhileStatement';

  visitBy<T>(Visitor<T> v) => v.visitDoWhile(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitDoWhile(this, arg);
}

/// Statement of form: `for ([init]; [condition]; [update]) [body]`
class ForStatement extends Statement {
  /// May be VariableDeclaration, Expression, or null.
  Node init;
  Expression condition; // May be null.
  Expression update; // May be null.
  Statement body;

  ForStatement(this.init, this.condition, this.update, this.body);

  forEach(callback) {
    if (init != null) callback(init);
    if (condition != null) callback(condition);
    if (update != null) callback(update);
    callback(body);
  }

  String toString() => 'ForStatement';

  visitBy<T>(Visitor<T> v) => v.visitFor(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitFor(this, arg);
}

/// Statement of form: `for ([left] in [right]) [body]`
class ForInStatement extends Statement {
  /// May be VariableDeclaration or Expression.
  Node left;
  Expression right;
  Statement body;

  ForInStatement(this.left, this.right, this.body);

  forEach(callback) {
    callback(left);
    callback(right);
    callback(body);
  }

  String toString() => 'ForInStatement';

  visitBy<T>(Visitor<T> v) => v.visitForIn(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitForIn(this, arg);
}

/// Statement of form: `function [function.name])([function.params]) { [function.body] }`.
class FunctionDeclaration extends Statement {
  FunctionNode function;

  FunctionDeclaration(this.function);

  forEach(callback) => callback(function);

  String toString() => 'FunctionDeclaration';

  visitBy<T>(Visitor<T> v) => v.visitFunctionDeclaration(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitFunctionDeclaration(this, arg);
}

/// Statement of form: `var [declarations];`
class VariableDeclaration extends Statement {
  List<VariableDeclarator> declarations;

  VariableDeclaration(this.declarations);

  forEach(callback) => declarations.forEach(callback);

  String toString() => 'VariableDeclaration';

  visitBy<T>(Visitor<T> v) => v.visitVariableDeclaration(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitVariableDeclaration(this, arg);
}

/// Variable declaration: `[name]` or `[name] = [init]`.
class VariableDeclarator extends Node {
  Name name;
  Expression init; // May be null.

  VariableDeclarator(this.name, this.init);

  forEach(callback) {
    callback(name);
    if (init != null) callback(init);
  }

  String toString() => 'VariableDeclarator';

  visitBy<T>(Visitor<T> v) => v.visitVariableDeclarator(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitVariableDeclarator(this, arg);
}

/// Statement of form: `debugger;`
class DebuggerStatement extends Statement {
  forEach(callback) {}

  String toString() => 'DebuggerStatement';

  visitBy<T>(Visitor<T> v) => v.visitDebugger(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitDebugger(this, arg);
}

///////

/// Superclass of all nodes that are expressions.
abstract class Expression extends Node {}

/// Expression of form: `this`
class ThisExpression extends Expression {
  forEach(callback) {}

  String toString() => 'ThisExpression';

  visitBy<T>(Visitor<T> v) => v.visitThis(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitThis(this, arg);
}

/// Expression of form: `[ [expressions] ]`
class ArrayExpression extends Expression {
  List<Expression>
      expressions; // May CONTAIN nulls for omitted elements: e.g. [1,2,,,]

  ArrayExpression(this.expressions);

  forEach(callback) {
    for (Expression exp in expressions) {
      if (exp != null) {
        callback(exp);
      }
    }
  }

  String toString() => 'ArrayExpression';

  visitBy<T>(Visitor<T> v) => v.visitArray(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitArray(this, arg);
}

/// Expression of form: `{ [properties] }`
class ObjectExpression extends Expression {
  List<Property> properties;

  ObjectExpression(this.properties);

  forEach(callback) => properties.forEach(callback);

  String toString() => 'ObjectExpression';

  visitBy<T>(Visitor<T> v) => v.visitObject(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitObject(this, arg);
}

/// Property initializer `[key]: [value]`, or getter `get [key] [value]`, or setter `set [key] [value]`.
///
/// For getters and setters, [value] is a [FunctionNode], otherwise it is an [Expression].
class Property extends Node {
  /// Literal or Name indicating the name of the property. Use [nameString] to get the name as a string.
  Node key;

  /// A [FunctionNode] (for getters and setters) or an [Expression] (for ordinary properties).
  Node value;

  /// May be "init", "get", or "set".
  String kind;

  Property(this.key, this.value, [this.kind = 'init']);
//  Property.getter(this.key, FunctionExpression this.value) : kind = 'get';
//  Property.setter(this.key, FunctionExpression this.value) : kind = 'set';

  bool get isInit => kind == 'init';
  bool get isGetter => kind == 'get';
  bool get isSetter => kind == 'set';
  bool get isAccessor => isGetter || isSetter;

  String get nameString => key is Name
      ? (key as Name).value
      : (key as LiteralExpression).value.toString();

  /// Returns the value as a FunctionNode. Useful for getters/setters.
  FunctionNode get function => value as FunctionNode;

  /// Returns the value as an Expression. Useful for non-getter/setters.
  Expression get expression => value as Expression;

  forEach(callback) {
    callback(key);
    callback(value);
  }

  String toString() => 'Property';

  visitBy<T>(Visitor<T> v) => v.visitProperty(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitProperty(this, arg);
}

/// Expression of form: `function [function.name]([function.params]) { [function.body] }`.
class FunctionExpression extends Expression {
  FunctionNode function;

  FunctionExpression(this.function);

  forEach(callback) => callback(function);

  String toString() => 'FunctionExpression';

  visitBy<T>(Visitor<T> v) => v.visitFunctionExpression(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitFunctionExpression(this, arg);
}

/// Comma-seperated expressions.
class SequenceExpression extends Expression {
  List<Expression> expressions;

  SequenceExpression(this.expressions);

  forEach(callback) => expressions.forEach(callback);

  String toString() => 'SequenceExpression';

  visitBy<T>(Visitor<T> v) => v.visitSequence(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitSequence(this, arg);
}

/// Expression of form: `+[argument]`, or using any of the unary operators:
/// `+, -, !, ~, typeof, void, delete`
class UnaryExpression extends Expression {
  String operator; // May be: +, -, !, ~, typeof, void, delete
  Expression argument;

  UnaryExpression(this.operator, this.argument);

  forEach(callback) => callback(argument);

  String toString() => 'UnaryExpression';

  visitBy<T>(Visitor<T> v) => v.visitUnary(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitUnary(this, arg);
}

/// Expression of form: `[left] + [right]`, or using any of the binary operators:
/// `==, !=, ===, !==, <, <=, >, >=, <<, >>, >>>, +, -, *, /, %, |, ^, &, &&, ||, in, instanceof`
class BinaryExpression extends Expression {
  Expression left;
  String
      operator; // May be: ==, !=, ===, !==, <, <=, >, >=, <<, >>, >>>, +, -, *, /, %, |, ^, &, &&, ||, in, instanceof
  Expression right;

  BinaryExpression(this.left, this.operator, this.right);

  forEach(callback) {
    callback(left);
    callback(right);
  }

  String toString() => 'BinaryExpression';

  visitBy<T>(Visitor<T> v) => v.visitBinary(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitBinary(this, arg);
}

/// Expression of form: `[left] = [right]` or `[left] += [right]` or using any of the assignment operators:
/// `=, +=, -=, *=, /=, %=, <<=, >>=, >>>=, |=, ^=, &=`
class AssignmentExpression extends Expression {
  Expression left;
  String operator; // May be: =, +=, -=, *=, /=, %=, <<=, >>=, >>>=, |=, ^=, &=
  Expression right;

  AssignmentExpression(this.left, this.operator, this.right);

  bool get isCompound => operator.length > 1;

  forEach(callback) {
    callback(left);
    callback(right);
  }

  String toString() => 'AssignmentExpression';

  visitBy<T>(Visitor<T> v) => v.visitAssignment(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitAssignment(this, arg);
}

/// Expression of form: `++[argument]`, `--[argument]`, `[argument]++`, `[argument]--`.
class UpdateExpression extends Expression {
  String operator; // May be: ++, --
  Expression argument;
  bool isPrefix;

  UpdateExpression(this.operator, this.argument, this.isPrefix);
  UpdateExpression.prefix(this.operator, this.argument) : isPrefix = true;
  UpdateExpression.postfix(this.operator, this.argument) : isPrefix = false;

  forEach(callback) => callback(argument);

  String toString() => 'UpdateExpression';

  visitBy<T>(Visitor<T> v) => v.visitUpdateExpression(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitUpdateExpression(this, arg);
}

/// Expression of form: `[condition] ? [then] : [otherwise]`.
class ConditionalExpression extends Expression {
  Expression condition;
  Expression then;
  Expression otherwise;

  ConditionalExpression(this.condition, this.then, this.otherwise);

  forEach(callback) {
    callback(condition);
    callback(then);
    callback(otherwise);
  }

  String toString() => 'ConditionalExpression';

  visitBy<T>(Visitor<T> v) => v.visitConditional(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitConditional(this, arg);
}

/// Expression of form: `[callee](..[arguments]..)` or `new [callee](..[arguments]..)`.
class CallExpression extends Expression {
  bool isNew;
  Expression callee;
  List<Expression> arguments;

  CallExpression(this.callee, this.arguments, {this.isNew = false});
  CallExpression.newCall(this.callee, this.arguments) : isNew = true;

  forEach(callback) {
    callback(callee);
    arguments.forEach(callback);
  }

  String toString() => 'CallExpression';

  visitBy<T>(Visitor<T> v) => v.visitCall(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitCall(this, arg);
}

/// Expression of form: `[object].[property].`
class MemberExpression extends Expression {
  Expression object;
  Name property;

  MemberExpression(this.object, this.property);

  forEach(callback) {
    callback(object);
    callback(property);
  }

  String toString() => 'MemberExpression';

  visitBy<T>(Visitor<T> v) => v.visitMember(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitMember(this, arg);
}

/// Expression of form: `[object][[property]]`.
class IndexExpression extends Expression {
  Expression object;
  Expression property;

  IndexExpression(this.object, this.property);

  forEach(callback) {
    callback(object);
    callback(property);
  }

  String toString() => 'IndexExpression';

  visitBy<T>(Visitor<T> v) => v.visitIndex(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitIndex(this, arg);
}

/// A [Name] that is used as an expression.
///
/// Note that "undefined", "NaN", and "Infinity" are name expressions, and not literals and one might expect.
class NameExpression extends Expression {
  Name name;

  NameExpression(this.name);

  forEach(callback) => callback(name);

  String toString() => 'NameExpression';

  visitBy<T>(Visitor<T> v) => v.visitNameExpression(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitNameExpression(this, arg);
}

/// A literal string, number, boolean or null.
///
/// Note that "undefined", "NaN", and "Infinity" are [NameExpression]s, and not literals and one might expect.
class LiteralExpression extends Expression {
  /// A string, number, boolean, or null value, indicating the value of the literal.
  dynamic value;

  /// The verbatim source-code representation of the literal.
  String raw;

  LiteralExpression(this.value, [this.raw]);

  bool get isString => value is String;
  bool get isNumber => value is num;
  bool get isBool => value is bool;
  bool get isNull => value == null;

  String get stringValue => value as String;
  num get numberValue => value as num;
  bool get boolValue => value as bool;

  /// Converts the value to a string
  String get toName => value.toString();

  forEach(callback) {}

  String toString() => 'LiteralExpression';

  visitBy<T>(Visitor<T> v) => v.visitLiteral(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitLiteral(this, arg);
}

/// A regular expression literal.
class RegexpExpression extends Expression {
  /// The entire literal, including slashes and flags.
  String regexp;

  RegexpExpression(this.regexp);

  forEach(callback) {}

  String toString() => 'RegexpExpression';

  visitBy<T>(Visitor<T> v) => v.visitRegexp(this);
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitRegexp(this, arg);
}
