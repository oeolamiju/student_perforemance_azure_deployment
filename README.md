# End-to-End Machine Learning Project — Student Performance Predictor

Predicting mathematics scores from demographic and prior-performance features, served by a Flask web app that runs as a Docker container on Azure App Service, with continuous deployment from GitHub Actions.

**Live demo:** [studentperformancecheck-adbwdkatavapf7gx.ukwest-01.azurewebsites.net/predictdata](https://studentperformancecheck-adbwdkatavapf7gx.ukwest-01.azurewebsites.net/predictdata)

---

## What this project is

A portfolio project that takes a machine learning problem end-to-end — from raw data through training, evaluation, packaging, and production deployment. Structured as a modular MLOps pipeline so components (ingestion, transformation, training, prediction) can be swapped or retrained independently, rather than as a single monolithic notebook.

- **Dataset:** Public student performance data (1,000 records)
- **Problem:** Supervised regression on mixed categorical and numerical tabular data
- **Target:** Mathematics score, predicted from seven features — gender, race/ethnicity, parental level of education, lunch type, test preparation course, reading score, writing score
- **Deployed model:** Linear Regression (R² = 0.880 on hold-out test set)
- **Delivery:** Docker image built by GitHub Actions, stored in Azure Container Registry, and served by Azure App Service

---

## Architecture

The project follows a modular MLOps pattern that separates each stage of the pipeline into its own component. Any single stage can be modified, retrained, or replaced without breaking the others.

```
raw data (notebook/data/stud.csv)
   │
   ▼
DataIngestion              →  artifacts/data.csv, train.csv, test.csv
   │   (80/20 train/test split, random_state=42)
   │
   ▼
DataTransformation         →  artifacts/preprocessor.pkl
   │   (SimpleImputer + StandardScaler for numeric features;
   │    SimpleImputer + OneHotEncoder + StandardScaler for categorical)
   │
   ▼
ModelTrainer               →  artifacts/model.pkl
   │   (compares 7 regressors with GridSearchCV;
   │    persists the best-performing model)
   │
   ▼
PredictPipeline
   │   (loads preprocessor + model at inference time)
   │
   ▼
Flask web app (app.py)
   │
   ▼
Docker image  →  Azure Container Registry  →  Azure App Service (UK West)
```

### Components

| Component | File | Responsibility |
|-----------|------|----------------|
| Data ingestion | `src/components/data_ingestion.py` | Reads raw CSV, splits into train/test, persists to `artifacts/`; running it executes the whole training pipeline |
| Data transformation | `src/components/data_transformation.py` | Builds a `ColumnTransformer` pipeline for numerical + categorical features |
| Model training | `src/components/model_trainer.py` | Trains and compares 7 regressors, hyperparameter-tunes via GridSearchCV, saves the best |
| Prediction pipeline | `src/pipeline/predict_pipeline.py` | Loads the fitted preprocessor + model, exposes a `predict()` method |
| Web application | `app.py` | Flask app that renders the input form and returns predictions |
| Custom exception | `src/exception.py` | Structured error handling with file + line context |
| Logging | `src/logger.py` | Writes a timestamped log file for each run under `logs/` |
| Container image | `Dockerfile`, `.dockerignore` | Packages the app and trained artifacts into a slim Python 3.10 image |
| CI/CD | `.github/workflows/main_studentperformancecheck.yml` | Builds the image and pushes it to Azure Container Registry on every push to `main` |

---

## Model selection

Nine regression algorithms were compared in `notebook/2. MODEL TRAINING.ipynb`, using default hyperparameters on the same 80/20 split. Results on the hold-out test set:

| Model | R² (test) |
|-------|-----------|
| Ridge Regression | 0.881 |
| **Linear Regression** *(deployed)* | **0.880** |
| Random Forest Regressor | 0.853 |
| CatBoost Regressor | 0.852 |
| AdaBoost Regressor | 0.847 |
| XGBRegressor | 0.828 |
| Lasso Regression | 0.825 |
| K-Neighbors Regressor | 0.784 |
| Decision Tree Regressor | 0.732 |

**Why Linear Regression was chosen for deployment.** Ridge and Linear scored within 0.001 of one another — a difference below any meaningful signal band. Linear Regression was selected on interpretability grounds: it produces coefficients that can be explained to a non-technical audience, and the marginal accuracy trade-off is negligible. This is a deliberate choice in favour of transparency over a fractional gain in test-set score.

The training pipeline (`src/components/model_trainer.py`) then tunes seven regressors with GridSearchCV (3-fold cross-validation) and saves the best scorer on the test set. The saved `artifacts/model.pkl` is a Linear Regression model with R² = 0.880 on the hold-out set.

---

## Web app

| Route | Method | What it does |
|-------|--------|--------------|
| `/` | GET | Landing page with a link to the predictor |
| `/predictdata` | GET | Input form for the seven features |
| `/predictdata` | POST | Runs the prediction pipeline and shows the predicted mathematics score |

---

## Running locally

```bash
git clone https://github.com/oeolamiju/student_perforemance_azure_deployment.git
cd student_perforemance_azure_deployment
```

**Option A — Docker** (the same image that runs in production):

```bash
docker build -t studentperformance .
docker run --rm -p 8080:80 studentperformance
# Open http://127.0.0.1:8080/predictdata
```

**Option B — Python 3.10** (the version the Docker image uses):

```bash
# 1. Create a virtual environment
python -m venv venv
source venv/bin/activate          # macOS / Linux
# venv\Scripts\activate           # Windows

# 2. Install dependencies
pip install -r requirements.txt

# 3. Optional: retrain (regenerates everything in artifacts/)
python src/components/data_ingestion.py

# 4. Run the web app
python app.py
# Open http://127.0.0.1/predictdata
# The app listens on port 80, as it does in the container; on Linux, ports below 1024 need sudo
```

---

## Deployment

The application runs as a Docker container on **Azure App Service (Web App for Containers, Linux)** in the UK West region. Every push to `main` redeploys it:

```
git push to main
   │
   ▼
GitHub Actions (.github/workflows/main_studentperformancecheck.yml)
   │   docker build, then push :latest and :<commit-sha>
   │
   ▼
Azure Container Registry (testdockerniyi.azurecr.io/studentperformance1)
   │   webhook fires when :latest is pushed
   │
   ▼
Azure App Service (studentperformancecheck)
       restarts, pulls the new image, serves the app on port 80
```

- **Image:** `python:3.10-slim-bookworm` base. Dependencies are installed before the code is copied, so code-only changes reuse the cached dependency layer; `.dockerignore` keeps notebooks, virtual environments and Git history out of the image.
- **Registry authentication:** the registry's admin credentials, stored as the GitHub secrets `ACR_USERNAME` and `ACR_PASSWORD`. App Service pulls the image with the same credentials.
- **Continuous deployment:** enabled in Deployment Center ("Continuous deployment for the main container"), which registers the registry webhook. The webhook needs **SCM Basic Auth Publishing Credentials** turned on for the web app.
- **Live URL:** [studentperformancecheck-adbwdkatavapf7gx.ukwest-01.azurewebsites.net/predictdata](https://studentperformancecheck-adbwdkatavapf7gx.ukwest-01.azurewebsites.net/predictdata)

### Reproducing the deployment

1. Create an Azure Container Registry and enable its admin user (**Settings → Access keys**).
2. Build and push the image once:
   ```bash
   docker login <registry>.azurecr.io
   docker build -t <registry>.azurecr.io/studentperformance1:latest .
   docker push <registry>.azurecr.io/studentperformance1:latest
   ```
3. Create a Linux Web App that publishes a **Container**, using that image and port 80.
4. In the web app, turn on **Configuration → General settings → SCM Basic Auth Publishing Credentials**, then tick **Deployment Center → Containers → Continuous deployment for the main container** and apply.
5. In the GitHub repository, add the `ACR_USERNAME` and `ACR_PASSWORD` secrets from the registry's **Access keys** page, and update `REGISTRY` / `IMAGE` in the workflow if your names differ.

---

## Tech stack

- **Language:** Python 3.10
- **Modelling:** scikit-learn, XGBoost, CatBoost
- **Web framework:** Flask
- **Front end:** HTML + inline CSS (templates in `templates/`)
- **Containerisation:** Docker
- **CI/CD:** GitHub Actions, Azure Container Registry
- **Hosting:** Azure App Service — Web App for Containers (Linux)
- **Version control:** Git + GitHub

---

## What this project demonstrates

- **Modular MLOps pattern** — separated concerns for ingestion, transformation, training, and inference; each component swappable without touching the rest
- **Honest model selection** — comparison across nine candidates, deployed the one that best balances accuracy and interpretability rather than just the highest test-set score
- **Engineering discipline** — structured exception handling, per-run log files, reproducible pipeline (the same scripts that trained the deployed model regenerate all artifacts locally)
- **Containerised CI/CD** — every push to `main` builds a Docker image in GitHub Actions, pushes it to Azure Container Registry, and App Service redeploys it through a registry webhook
- **End-to-end delivery** — from raw CSV through to a live, publicly-accessible web endpoint

---

## Project structure

```
student_perforemance_azure_deployment/
├── .github/workflows/
│   └── main_studentperformancecheck.yml   # CI/CD: build the image, push to ACR
├── Dockerfile                             # Container image definition
├── .dockerignore                          # Keeps notebooks, venvs and .git out of the image
├── app.py                                 # Flask web application
├── requirements.txt
├── setup.py
├── artifacts/                             # Trained model, preprocessor and CSV splits (committed; copied into the image)
├── notebook/
│   ├── data/stud.csv                      # Raw dataset
│   ├── 1 . EDA STUDENT PERFORMANCE .ipynb
│   └── 2. MODEL TRAINING.ipynb
├── src/
│   ├── components/
│   │   ├── data_ingestion.py
│   │   ├── data_transformation.py
│   │   └── model_trainer.py
│   ├── pipeline/
│   │   ├── predict_pipeline.py
│   │   └── train_pipeline.py              # Placeholder; training runs from data_ingestion.py
│   ├── exception.py
│   ├── logger.py
│   └── utils.py
└── templates/
    ├── index.html
    └── home.html
```

---

## Author

**Olaniyi (Niyi) Olamiju** — Data & AI professional, Greater Manchester, UK
[LinkedIn](https://www.linkedin.com/in/niyiolamiju/) · [GitHub](https://github.com/oeolamiju)

---

*Built as a portfolio piece to demonstrate end-to-end ML delivery discipline. Comments and pull requests welcome.*
