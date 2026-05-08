#!/bin/bash

set -e

echo "📦 Creating virtual environment..."

# create venv
python3 -m venv venv

echo "🔌 Activating virtual environment..."

# activate venv
source venv/bin/activate

echo "⬆️ Upgrading pip..."

pip install --upgrade pip

echo "🎮 Installing pygame + python-osc..."

pip install pygame python-osc

echo "✅ Done!"
echo ""
echo "👉 To use the environment, run:"
echo "   source venv/bin/activate"
echo "   python main.py"
