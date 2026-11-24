class Priv { ~Priv(); public: Priv(); int v; };
struct PrivS { private: ~PrivS(); public: PrivS(); int v; };
struct ProtS { protected: ~ProtS(); public: ProtS(); int v; };
struct Ok { ~Ok(); Ok(); int v; };
class OkClass { public: ~OkClass(); OkClass(); int v; };
