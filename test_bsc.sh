#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-n <block_number>] [-c <chain>]"
    echo "  -n: Specify the tip block number (default: 5M)"
    echo "      Examples: 500000, 0.5M, 1M, 5M, 10M, 100K, 2.5M"
    echo "      Supports: exact numbers, K/k for thousands, M/m for millions"
    echo "  -c: Specify the blockchain network (default: bsc)"
    echo "      Options: bsc (mainnet), bsc-testnet"
    echo ""
    echo "Examples:"
    echo "  $0                    # Test BSC mainnet with 5M blocks"
    echo "  $0 -n 1M             # Test BSC mainnet with 1M blocks"
    echo "  $0 -c bsc-testnet     # Test BSC testnet with 5M blocks"
    echo "  $0 -n 2M -c bsc-testnet  # Test BSC testnet with 2M blocks"
    exit 1
}

# Function to convert block number notation to actual number
parse_block_number() {
    local input=$1
    case $input in
        *K|*k)
            # Remove K/k and multiply by 1000
            local num=${input%[Kk]}
            echo $((${num%.*} * 1000))
            ;;
        *M|*m)
            # Remove M/m and multiply by 1000000
            local num=${input%[Mm]}
            # Handle decimal notation like 0.5M
            if [[ $num == *.* ]]; then
                local integer_part=${num%.*}
                local decimal_part=${num#*.}
                echo $(( (integer_part * 1000000) + (decimal_part * 100000) ))
            else
                echo $((num * 1000000))
            fi
            ;;
        *)
            # Assume it's already a number
            echo "$input"
            ;;
    esac
}

# Function to get block hash for given block number by querying BSC network
get_block_hash() {
    local block_notation=$1
    local chain=$2
    local block_number=$(parse_block_number "$block_notation")
    
    # Convert to hex
    local block_hex=$(printf "0x%x" "$block_number")
    
    echo "Querying BSC $chain for block #$block_number ($block_hex)..." >&2
    
    # BSC RPC endpoints based on network
    local rpc_endpoints=()
    if [ "$chain" == "bsc-testnet" ]; then
        rpc_endpoints=(
            "https://data-seed-prebsc-1-s1.binance.org:8545/"
            "https://data-seed-prebsc-2-s1.binance.org:8545/"
            "https://data-seed-prebsc-1-s2.binance.org:8545/"
            "https://data-seed-prebsc-2-s2.binance.org:8545/"
        )
    else
        # Default to mainnet
        rpc_endpoints=(
            "https://bsc-dataseed.binance.org/"
            "https://bsc-dataseed1.defibit.io/"
            "https://bsc-dataseed1.ninicoin.io/"
            "https://bsc-dataseed2.defibit.io/"
        )
    fi
    
    for rpc_url in "${rpc_endpoints[@]}"; do
        echo "Trying RPC endpoint: $rpc_url" >&2
        
        # JSON-RPC call to get block by number
        local response=$(curl -s -X POST "$rpc_url" \
            -H "Content-Type: application/json" \
            -d "{
                \"jsonrpc\": \"2.0\",
                \"method\": \"eth_getBlockByNumber\",
                \"params\": [\"$block_hex\", false],
                \"id\": 1
            }" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            # Extract block hash from JSON response
            local block_hash=$(echo "$response" | grep -o '"hash":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)
            
            if [ -n "$block_hash" ] && [ "$block_hash" != "null" ]; then
                echo "Successfully retrieved block hash: $block_hash" >&2
                echo "$block_hash"
                return 0
            fi
        fi
        
        echo "Failed to get response from $rpc_url, trying next..." >&2
    done
    
    echo "Error: Could not retrieve block hash for block #$block_number from any RPC endpoint"
    echo "Please check your internet connection and try again."
    exit 1
}

# Parse command line arguments
block_number="5M"  # Default to 5M blocks
chain="bsc"        # Default to mainnet

while getopts "n:c:h" opt; do
    case $opt in
        n)
            block_number="$OPTARG"
            ;;
        c)
            chain="$OPTARG"
            ;;
        h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

# Validate chain parameter
if [[ "$chain" != "bsc" && "$chain" != "bsc-testnet" ]]; then
    echo "Error: Invalid chain '$chain'. Supported chains: bsc, bsc-testnet"
    usage
fi

# Get the corresponding block hash
tip_block=$(get_block_hash "$block_number" "$chain")

# Create results directory if it doesn't exist
mkdir -p ./test_results

# Generate well-named result file
timestamp=$(date +"%Y%m%d_%H%M%S")
hostname=$(hostname -s)
network_name=$(echo "$chain" | sed 's/bsc-testnet/testnet/' | sed 's/bsc/mainnet/')
result_file="./test_results/bsc_${network_name}_test_${block_number}_${timestamp}_${hostname}.log"

echo "## Testing BSC $network_name block syncing for the first $block_number blocks"
echo "Chain: $chain"
echo "Using tip block: $tip_block"
echo "Starting at: $(date)"
echo "Results will be saved to: $result_file"

# Get git repository information
git_remote_url=$(git remote get-url origin 2>/dev/null || echo "Unknown")
git_branch=$(git branch --show-current 2>/dev/null || echo "Unknown")
git_commit=$(git rev-parse HEAD 2>/dev/null || echo "Unknown")

echo ""
echo "Git Repository Information:"
echo "Remote URL: $git_remote_url"
echo "Current branch: $git_branch"
echo "Commit hash: $git_commit"
echo ""

# Set network-specific directory name
if [ "$chain" == "bsc-testnet" ]; then
    data_dir="fullnode_bsc_testnet"
else
    data_dir="fullnode_bsc_mainnet"
fi

echo "Using data directory: ./$data_dir"

# Save initial info to result file
{
    echo "BSC ${network_name^} Test Results"
    echo "========================"
    echo "Test started at: $(date)"
    echo "Network: BSC $network_name"
    echo "Chain parameter: $chain"
    echo "Data directory: ./$data_dir"
    echo "Block number: $block_number"
    echo "Tip block hash: $tip_block"
    echo "Hostname: $(hostname)"
    echo "OS: $(uname -s)"
    echo "Working directory: $(pwd)"
    echo ""
    echo "Git Repository Information:"
    echo "Remote URL: $git_remote_url"
    echo "Current branch: $git_branch"
    echo "Commit hash: $git_commit"
    echo "========================"
    echo ""
} > "$result_file"

rm -rf ./$data_dir
cargo clean && cargo update 

# Detect OS and build accordingly
os=$(uname -s)
if [ "$os" == "Darwin" ]; then
    echo "Building for Darwin"
    cargo build --bin reth-bsc --release
else
    echo "Building for Linux"
    RUSTFLAGS='-C link-arg=-lgcc' cargo build --bin reth-bsc --release
fi

# Record start time
start_time=$(date +%s)

RUST_LOG=INFO ./target/release/reth-bsc node \
    --chain=$chain \
    --http --http.api="eth, net, txpool, web3, rpc" \
    --datadir ./$data_dir/data --log.file.directory ./$data_dir/logs \
    --trusted-peers=enode://551c8009f1d5bbfb1d64983eeb4591e51ad488565b96cdde7e40a207cfd6c8efa5b5a7fa88ed4e71229c988979e4c720891287ddd7d00ba114408a3ceb972ccb@34.245.203.3:30311,enode://c637c90d6b9d1d0038788b163a749a7a86fed2e7d0d13e5dc920ab144bb432ed1e3e00b54c1a93cecba479037601ba9a5937a88fe0be949c651043473c0d1e5b@34.244.120.206:30311,enode://bac6a548c7884270d53c3694c93ea43fa87ac1c7219f9f25c9d57f6a2fec9d75441bc4bad1e81d78c049a1c4daf3b1404e2bbb5cd9bf60c0f3a723bbaea110bc@3.255.117.110:30311,enode://94e56c84a5a32e2ef744af500d0ddd769c317d3c3dd42d50f5ea95f5f3718a5f81bc5ce32a7a3ea127bc0f10d3f88f4526a67f5b06c1d85f9cdfc6eb46b2b375@3.255.231.219:30311,enode://5d54b9a5af87c3963cc619fe4ddd2ed7687e98363bfd1854f243b71a2225d33b9c9290e047d738e0c7795b4bc78073f0eb4d9f80f572764e970e23d02b3c2b1f@34.245.16.210:30311,enode://41d57b0f00d83016e1bb4eccff0f3034aa49345301b7be96c6bb23a0a852b9b87b9ed11827c188ad409019fb0e578917d722f318665f198340b8a15ae8beff36@34.245.72.231:30311,enode://1bb269476f62e99d17da561b1a6b0d0269b10afee029e1e9fdee9ac6a0e342ae562dfa8578d783109b80c0f100a19e03b057f37b2aff22d8a0aceb62020018fe@54.78.102.178:30311,enode://3c13113538f3ca7d898d99f9656e0939451558758fd9c9475cff29f020187a56e8140bd24bd57164b07c3d325fc53e1ef622f793851d2648ed93d9d5a7ce975c@34.254.238.155:30311,enode://d19fd92e4f061d82a92e32d377c568494edcc36883a02e9d527b69695b6ae9e857f1ace10399c2aee4f71f5885ca3fe6342af78c71ad43ec1ca890deb6aaf465@34.247.29.116:30311,enode://c014bbf48209cdf8ca6d3bf3ff5cf2fade45104283dcfc079df6c64e0f4b65e4afe28040fa1731a0732bd9cbb90786cf78f0174b5de7bd5b303088e80d8e6a83@54.74.101.143:30311 \
    --metrics 0.0.0.0:6060 \
    --debug.tip $tip_block \
    --debug.terminate \
    --log.file.max-size 1000 \
    --log.file.max-files 1000

# Record end time and calculate duration
end_time=$(date +%s)
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

# Prepare final summary
final_summary=""
final_summary+="================================================\n"
final_summary+="Test block-syncing for BSC $network_name for the first $block_number blocks\n"
final_summary+="Chain: $chain\n"
if [ $minutes -gt 0 ]; then
    final_summary+="It takes $minutes mins $seconds secs\n"
else
    final_summary+="It takes $seconds secs\n"
fi
final_summary+="The current directory is $(pwd)\n"
final_summary+="Test completed at: $(date)\n"
final_summary+="================================================"

# Output final summary to console
echo ""
echo -e "$final_summary"

# Append final summary to result file
{
    echo "Test Execution Summary"
    echo "====================="
    echo "Duration: $duration seconds"
    if [ $minutes -gt 0 ]; then
        echo "Formatted time: $minutes mins $seconds secs"
    else
        echo "Formatted time: $seconds secs"
    fi
    echo "Test completed at: $(date)"
    echo ""
    echo -e "$final_summary"
} >> "$result_file"

echo ""
echo "Test results have been saved to: $result_file"