`git clone https://github.com/theJayTea/WritingTools.git`
`cd WritingTools`

C'est mieux d'installer déjà un environnement virtuel avant d'installer les dépendances. Pour ne pas les installer de façon générale
`py -3 -m venv myvenv`
`myvenv\Scripts\activate`
puis
`pip install -r requirements.txt`

cd .\Windows_and_Linux & myvenv\Scripts\activate & python main.py

Lancer le script
`python main.py`

compiler
python pyinstaller-build-script.py

## Corrections

Removed HARM_CATEGORY_CIVIC_INTEGRITY as it's deprecated in current Gemini API version. It was making the script crash.

## Améliorations
- [ ] Après changement du LLM fermer puis rouvrir l'application
- [x] Commande Sur sélection Sur texte non éditable
- [ ] Si on développe via un script ne pas afficher le message d'update. Donc réussir à détecter si on développe via un script
- [ ] bug dans responseWindow seule la 1ère réponse peut être copiée. Mettre un bouton de copie en haut de chaque cadre. ResponseWindow/copyButton
