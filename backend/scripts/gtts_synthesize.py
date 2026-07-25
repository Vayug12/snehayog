import sys
import argparse
from gtts import gTTS

def main():
    parser = argparse.ArgumentParser(description='gTTS Synthesis Bridge')
    parser.add_argument('--text', help='Text to synthesize')
    parser.add_argument('--file', help='Path to UTF-8 text file to synthesize')
    parser.add_argument('--lang', default='en', help='Language code')
    parser.add_argument('--output', required=True, help='Output file path')
    
    args = parser.parse_args()
    
    text = args.text
    if args.file:
        with open(args.file, 'r', encoding='utf-8') as f:
            text = f.read()
            
    if not text:
        print("Error: No text provided via --text or --file", file=sys.stderr)
        sys.exit(1)
    
    try:
        tts = gTTS(text=text, lang=args.lang or 'en')
        tts.save(args.output)
        print(f"Successfully synthesized to {args.output}")
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
