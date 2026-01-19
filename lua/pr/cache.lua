local M = {}

local data_path = vim.fn.stdpath("data") .. "/pr-nvim"
local reviews_file = data_path .. "/reviews.json"

function M.ensure_dir()
  vim.fn.mkdir(data_path, "p")
end

function M.save_review(review)
  if not review then return end
  
  M.ensure_dir()
  
  local key = string.format("%s/%s#%d", review.owner, review.repo, review.number)
  local reviews = M.load_all_reviews()
  
  reviews[key] = {
    owner = review.owner,
    repo = review.repo,
    number = review.number,
    reviewed = review.reviewed,
    pending_comments = review.pending_comments,
    file_index = review.file_index,
    timestamp = os.time(),
  }
  
  local f = io.open(reviews_file, "w")
  if f then
    f:write(vim.json.encode(reviews))
    f:close()
  end
end

function M.load_review(owner, repo, number)
  local key = string.format("%s/%s#%d", owner, repo, number)
  local reviews = M.load_all_reviews()
  return reviews[key]
end

function M.load_all_reviews()
  local f = io.open(reviews_file, "r")
  if not f then return {} end
  
  local content = f:read("*a")
  f:close()
  
  local ok, reviews = pcall(vim.json.decode, content)
  if not ok then return {} end
  
  return reviews or {}
end

function M.clear_review(owner, repo, number)
  local key = string.format("%s/%s#%d", owner, repo, number)
  local reviews = M.load_all_reviews()
  reviews[key] = nil
  
  local f = io.open(reviews_file, "w")
  if f then
    f:write(vim.json.encode(reviews))
    f:close()
  end
end

-- Diff cache (in-memory for session)
M.diff_cache = {}

function M.get_diff(owner, repo, number)
  local key = string.format("%s/%s#%d", owner, repo, number)
  return M.diff_cache[key]
end

function M.set_diff(owner, repo, number, diff)
  local key = string.format("%s/%s#%d", owner, repo, number)
  M.diff_cache[key] = diff
end

return M
