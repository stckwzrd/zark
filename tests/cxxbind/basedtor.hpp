#pragma once
class Secret {
public:
    int n;
private:
    ~Secret();
};

class Child : public Secret {
public:
    int m;
};

class DeletedBase {
public:
    int n;
    ~DeletedBase() = delete;
};

class DeletedChild : public DeletedBase {
public:
    int m;
};
