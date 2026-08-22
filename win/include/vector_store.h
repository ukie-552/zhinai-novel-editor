// vector_store.h - 本地向量库, 对应原 macos/VectorStore.swift
// 第一版: 内存级简易版 (分块 + 余弦), 后续可换 sqlite-vss / hnswlib.
#pragma once
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace zhinai::vector {

struct Hit {
    std::string source;     // 来源 id / 文本片段
    std::string snippet;
    double score = 0.0;
};

// 导入一个文本, 自动分块入库.
void importText(const std::string& source, const std::string& text);

// 关键词版粗排 (第一版用词频, 后续可换 embedding).
std::vector<Hit> search(const std::string& query, int topK = 5);

nlohmann::json stats();

}  // namespace zhinai::vector
