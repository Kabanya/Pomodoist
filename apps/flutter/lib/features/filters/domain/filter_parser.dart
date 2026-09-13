sealed class FilterAst {
  const FilterAst();
}

class AndNode extends FilterAst {
  const AndNode(this.left, this.right);
  final FilterAst left;
  final FilterAst right;
}

class OrNode extends FilterAst {
  const OrNode(this.left, this.right);
  final FilterAst left;
  final FilterAst right;
}

class NotNode extends FilterAst {
  const NotNode(this.node);
  final FilterAst node;
}

class PredicateNode extends FilterAst {
  const PredicateNode(this.predicate);
  final FilterPredicate predicate;
}

class FilterPredicate {
  const FilterPredicate(this.name, [this.value]);
  final String name;
  final String? value;

  @override
  String toString() => value == null ? name : '$name:$value';
}

class FilterParser {
  FilterAst parse(String query) {
    final tokens = _tokenize(query);
    final state = _ParserState(tokens);
    final ast = _parseOr(state);
    if (!state.isDone) {
      throw FormatException('Unexpected token: ${state.peek}');
    }
    return ast;
  }

  FilterAst _parseOr(_ParserState state) {
    var node = _parseAnd(state);
    while (state.match('|')) {
      node = OrNode(node, _parseAnd(state));
    }
    return node;
  }

  FilterAst _parseAnd(_ParserState state) {
    var node = _parseUnary(state);
    while (state.match('&')) {
      node = AndNode(node, _parseUnary(state));
    }
    return node;
  }

  FilterAst _parseUnary(_ParserState state) {
    if (state.match('!')) {
      return NotNode(_parseUnary(state));
    }
    return _parsePrimary(state);
  }

  FilterAst _parsePrimary(_ParserState state) {
    if (state.match('(')) {
      final node = _parseOr(state);
      state.expect(')');
      return node;
    }
    final token = state.consume();
    if (token == null) {
      throw const FormatException('Expected predicate');
    }
    return PredicateNode(_predicate(token));
  }

  FilterPredicate _predicate(String token) {
    if (token.startsWith('#')) {
      return FilterPredicate('project', token.substring(1));
    }
    if (token.startsWith('@')) {
      return FilterPredicate('label', token.substring(1));
    }
    if (RegExp(r'^p[1-4]$', caseSensitive: false).hasMatch(token)) {
      return FilterPredicate('priority', token.substring(1));
    }
    if (token.startsWith('estimate:')) {
      return FilterPredicate('estimate', token.substring('estimate:'.length));
    }
    if (token.startsWith('focus:')) {
      return FilterPredicate('focus', token.substring('focus:'.length));
    }
    if (token.startsWith('focused:')) {
      return FilterPredicate('focused', token.substring('focused:'.length));
    }
    if (token == 'no date') {
      return const FilterPredicate('no_date');
    }
    if (token == 'not focused') {
      return const FilterPredicate('not_focused');
    }
    return FilterPredicate(token);
  }

  List<String> _tokenize(String query) {
    final normalized = query
        .replaceAll('no date', 'no_date_tmp')
        .replaceAll('not focused', 'not_focused_tmp');
    final raw = RegExp(
      r'(\(|\)|&|\||!|[^\s()&|!]+)',
    ).allMatches(normalized).map((m) => m.group(0)!).toList();
    return raw
        .map(
          (token) => token
              .replaceAll('no_date_tmp', 'no date')
              .replaceAll('not_focused_tmp', 'not focused'),
        )
        .toList();
  }
}

class _ParserState {
  _ParserState(this.tokens);

  final List<String> tokens;
  int index = 0;

  bool get isDone => index >= tokens.length;
  String? get peek => isDone ? null : tokens[index];

  bool match(String token) {
    if (peek == token) {
      index += 1;
      return true;
    }
    return false;
  }

  void expect(String token) {
    if (!match(token)) {
      throw FormatException('Expected $token, got $peek');
    }
  }

  String? consume() {
    if (isDone) {
      return null;
    }
    final token = tokens[index];
    index += 1;
    return token;
  }
}
