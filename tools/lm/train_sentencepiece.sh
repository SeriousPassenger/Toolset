#!/usr/bin/env bash

###############################################################################
# train_sentencepiece.sh
#
# This script trains a SentencePiece model (unigram) with optional user-defined
# symbols. It checks for common errors (e.g., missing input file, uninstalled
# spm_train) and provides helpful usage instructions.
#
# Usage:
#   ./train_sentencepiece.sh <input_file> <model_name> <vocab_size> [max_sentences]
#
# Example:
#   ./train_sentencepiece.sh passwords.lst pass_unigram 32000 500000
#
# Notes:
#   - By default, it uses up to 50,000,000 lines from the input if max_sentences
#     is not specified.
#   - It assumes spm_train (from the SentencePiece toolkit) is in your PATH.
###############################################################################

#--- COLOR DEFINITIONS (for better terminal output) ---------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#--- CLI ARGUMENTS ------------------------------------------------------------
INPUT_FILE="$1"
MODEL_NAME="$2"
VOCAB_SIZE="$3"
MAX_SENTENCES="$4"

#--- SPECIAL SYMBOLS ----------------------------------------------------------
BOS_TOKEN="<BOS>"
EOS_TOKEN="<EOS>"
DEFINED_SYMBOLS="$BOS_TOKEN,$EOS_TOKEN"

#--- DEFAULTS -----------------------------------------------------------------
DEFAULT_MAX_SENTENCES=50000000

#--- USAGE FUNCTION -----------------------------------------------------------
usage() {
  echo -e "${BOLD}Usage:${NC} $0 <input_file> <model_name> <vocab_size> [max_sentences]"
  echo "       E.g., $0 passwords.lst pass_unigram 32000 500000"
  echo
  echo "    input_file      Path to your text data"
  echo "    model_name      Prefix for the generated *.model and *.vocab files"
  echo "    vocab_size      Size of the vocabulary to build"
  echo "    max_sentences   (optional) Maximum lines to consider from input. Default: ${DEFAULT_MAX_SENTENCES}"
  echo
  echo "    This script uses the following user-defined symbols:"
  echo "      - $BOS_TOKEN"
  echo "      - $EOS_TOKEN"
  echo
  echo "    Make sure 'spm_train' (SentencePiece) is installed and in your PATH."
}

#--- CHECK FOR HELP -----------------------------------------------------------
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

#--- VALIDATE REQUIRED ARGS ---------------------------------------------------
if [ -z "$INPUT_FILE" ] || [ -z "$MODEL_NAME" ] || [ -z "$VOCAB_SIZE" ]; then
  echo -e "${RED}[ERROR] Missing required arguments.${NC}"
  usage
  exit 1
fi

#--- CHECK IF SPm TRAIN EXISTS IN PATH ----------------------------------------
if ! command -v spm_train &> /dev/null; then
  echo -e "${RED}[ERROR] 'spm_train' command not found. Please install SentencePiece.${NC}"
  exit 1
fi

#--- CHECK INPUT FILE ---------------------------------------------------------
if [ ! -f "$INPUT_FILE" ]; then
  echo -e "${RED}[ERROR] Input file '$INPUT_FILE' does not exist.${NC}"
  exit 1
fi

#--- CHECK NUMERIC ARGS -------------------------------------------------------
# Check that VOCAB_SIZE is a valid positive integer
if ! [[ "$VOCAB_SIZE" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}[ERROR] vocab_size must be a positive integer. Got: $VOCAB_SIZE${NC}"
  exit 1
fi

# If max_sentences is empty, set a default. Otherwise, validate it.
if [ -z "$MAX_SENTENCES" ]; then
  MAX_SENTENCES=$DEFAULT_MAX_SENTENCES
else
  if ! [[ "$MAX_SENTENCES" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}[ERROR] max_sentences must be a positive integer. Got: $MAX_SENTENCES${NC}"
    exit 1
  fi
fi

#--- PRINT DEBUG INFO ---------------------------------------------------------
echo -e "${CYAN}[INFO] Training file:${NC}          $INPUT_FILE"
echo -e "${CYAN}[INFO] Output model prefix:${NC}   $MODEL_NAME"
echo -e "${CYAN}[INFO] Vocabulary size:${NC}       $VOCAB_SIZE"
echo -e "${CYAN}[INFO] Max sentences:${NC}         $MAX_SENTENCES"
echo -e "${CYAN}[INFO] User-defined symbols:${NC}  $DEFINED_SYMBOLS"
echo
echo -e "${BOLD}Starting SentencePiece training now...${NC}"
echo

#--- RUN SPM_TRAIN ------------------------------------------------------------
spm_train \
  --input="$INPUT_FILE" \
  --model_prefix="$MODEL_NAME" \
  --vocab_size="$VOCAB_SIZE" \
  --model_type=unigram \
  --character_coverage=1.0 \
  --shuffle_input_sentence=true \
  --input_sentence_size="$MAX_SENTENCES" \
  --user_defined_symbols="$DEFINED_SYMBOLS" \
  --hard_vocab_limit=false

#--- CHECK EXIT STATUS --------------------------------------------------------
if [ $? -ne 0 ]; then
  echo -e "${RED}[ERROR] SentencePiece training failed. Check logs above.${NC}"
  exit 1
fi

#--- SUCCESS MESSAGE ----------------------------------------------------------
echo
echo -e "${GREEN}Training completed successfully!${NC} Your model files:"
echo -e "  - ${MODEL_NAME}.model"
echo -e "  - ${MODEL_NAME}.vocab"
echo
echo "    Enjoy your new Unigram-based tokenizer!"
