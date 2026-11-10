const int sensorPins[4] = {A1, A2, A3, A6};

void setup() {
  Serial.begin(9600);
  // Rimosso il while(!Serial) per evitare blocchi se il plotter non è avviato all'istante
  delay(1500); 
  
  // Imposta la risoluzione a 12 bit (0-4095)
  analogReadResolution(12);
}

void loop() {
  float voltages[4];
  
  // Legge e converte i 4 sensori in tensione (0 - 3.3V)
  for (int i = 0; i < 4; i++) {
    int sensorValue = analogRead(sensorPins[i]);
    voltages[i] = sensorValue * (5 / 4095.0);
  }
  
  // Stampa formattata per il Plotter Seriale (Etichetta:Valore separate da virgole)
  Serial.print("S1:");
  Serial.print(voltages[1], 2);
  Serial.print(",");
  Serial.print("S2:");
  Serial.print(voltages[2], 2);
  Serial.print(",");
  Serial.print("S3:");
  Serial.print(voltages[3], 2);
  Serial.print(",");
  Serial.print("S4:");
  Serial.println(voltages[4], 2); // println va a capo e chiude la riga del grafico
  
  delay(100); // Frequenza di campionamento di 10 Hz per il grafico
}