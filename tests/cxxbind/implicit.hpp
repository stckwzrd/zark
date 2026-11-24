struct ImplicitOwn { ~ImplicitOwn(); int n; };
struct WithArg { ~WithArg(); WithArg(int); int n; };
class ClassOwn { public: ~ClassOwn(); int n; };
